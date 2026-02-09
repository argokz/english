"""Gemini API: generate word lists, enrich single word. Optional: embeddings for pgvector."""
import os
import re
import json
from typing import Any

import google.generativeai as genai
from app.config import settings

genai.configure(api_key=os.environ.get("GEMINI_API_KEY") or settings.gemini_api_key)


def _model():
    model_name = settings.gemini_model or "gemini-1.5-flash"
    return genai.GenerativeModel(model_name)


def generate_word_list(level: str | None = None, topic: str | None = None, count: int = 20) -> list[dict[str, str]]:
    """Generate list of words with translation, example, and IPA transcription. Returns list of {word, translation, example, transcription}."""
    if not level and not topic:
        level = "A1"
    prompt = f"""Generate {count} frequent English words for learners.
{"Use CEFR level: " + level + "." if level else ""}
{"Use topic/theme: " + topic + "." if topic else ""}
For each word provide: 1) English word, 2) Russian translation, 3) one short example sentence in English, 4) IPA phonetic transcription (e.g. ˈæpl for apple).
Output format: one line per word, pipe-separated: word | translation | example | transcription
Example: apple | яблоко | I eat an apple every day. | ˈæpl
Do not add numbering or extra text. Only lines in format: word | translation | example | transcription"""

    response = _model().generate_content(prompt)
    text = (response.text or "").strip()
    result = []
    for line in text.split("\n"):
        line = line.strip()
        if not line or "|" not in line:
            continue
        parts = [p.strip() for p in line.split("|", 3)]
        if len(parts) >= 2:
            transcription = parts[3] if len(parts) > 3 else None
            if transcription:
                transcription = transcription.strip("[]")
            result.append({
                "word": parts[0],
                "translation": parts[1],
                "example": parts[2] if len(parts) > 2 else None,
                "transcription": transcription or None,
            })
    return result[:count]


def enrich_word(word: str) -> dict[str, str]:
    """Get translation, example, and transcription for one word. Returns {translation, example, transcription}."""
    prompt = f"""For the English word "{word}" provide:
1) Russian translation (one word or short phrase)
2) One short example sentence in English using this word.
3) IPA phonetic transcription in square brackets (e.g., [ˈæpl])

Reply in JSON only: {{"translation": "...", "example": "...", "transcription": "..."}}"""

    response = _model().generate_content(prompt)
    text = (response.text or "").strip()
    # Extract JSON from response (may be wrapped in markdown)
    m = re.search(r"\{[^{}]*\"translation\"[^{}]*\"example\"[^{}]*\"transcription\"[^{}]*\}", text)
    if m:
        try:
            result = json.loads(m.group())
            # Clean transcription - remove brackets if present
            if "transcription" in result and result["transcription"]:
                result["transcription"] = result["transcription"].strip("[]")
            return result
        except json.JSONDecodeError:
            pass
    return {"translation": "", "example": "", "transcription": ""}


def get_pronunciation_url(word: str) -> str | None:
    """Generate pronunciation URL using Google TTS API. Returns URL or None."""
    try:
        # Use Google TTS API for pronunciation
        # Format: https://translate.google.com/translate_tts?ie=UTF-8&tl=en&client=tw-ob&q={word}
        import urllib.parse
        encoded_word = urllib.parse.quote(word)
        return f"https://translate.google.com/translate_tts?ie=UTF-8&tl=en&client=tw-ob&q={encoded_word}"
    except Exception:
        return None


def get_embedding(text: str) -> list[float] | None:
    """Get embedding vector for text (e.g. word or 'word: translation'). Returns 768-dim list or None."""
    try:
        result = genai.embed_content(
            model="models/text-embedding-004",
            content=text,
            task_type="retrieval_document",
        )
        if result and "embedding" in result:
            return result["embedding"]
    except Exception:
        pass
    return None
