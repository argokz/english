"""Gemini API: generate word lists, enrich single word. Optional: embeddings for pgvector."""
import os
import re
import json
from typing import Any

import google.generativeai as genai
from app.config import settings

genai.configure(api_key=os.environ.get("GEMINI_API_KEY") or settings.gemini_api_key)


def _model():
    return genai.GenerativeModel("gemini-1.5-flash")


def generate_word_list(level: str | None = None, topic: str | None = None, count: int = 20) -> list[dict[str, str]]:
    """Generate list of words. level e.g. A1, B2 or topic e.g. business, travel. Returns list of {word, translation, example}."""
    if not level and not topic:
        level = "A1"
    prompt = f"""Generate {count} frequent English words for learners.
{"Use CEFR level: " + level + "." if level else ""}
{"Use topic/theme: " + topic + "." if topic else ""}
For each word provide: the English word, Russian translation, and one short example sentence in English.
Output format: one line per word, pipe-separated: word | translation | example
Example: apple | яблоко | I eat an apple every day.
Do not add numbering or extra text. Only lines in format: word | translation | example"""

    response = _model().generate_content(prompt)
    text = (response.text or "").strip()
    result = []
    for line in text.split("\n"):
        line = line.strip()
        if not line or "|" not in line:
            continue
        parts = [p.strip() for p in line.split("|", 2)]
        if len(parts) >= 2:
            result.append({
                "word": parts[0],
                "translation": parts[1],
                "example": parts[2] if len(parts) > 2 else None,
            })
    return result[:count]


def enrich_word(word: str) -> dict[str, str]:
    """Get translation and example for one word. Returns {translation, example}."""
    prompt = f"""For the English word "{word}" provide:
1) Russian translation (one word or short phrase)
2) One short example sentence in English using this word.

Reply in JSON only: {{"translation": "...", "example": "..."}}"""

    response = _model().generate_content(prompt)
    text = (response.text or "").strip()
    # Extract JSON from response (may be wrapped in markdown)
    m = re.search(r"\{[^{}]*\"translation\"[^{}]*\"example\"[^{}]*\}", text)
    if m:
        try:
            return json.loads(m.group())
        except json.JSONDecodeError:
            pass
    return {"translation": "", "example": ""}


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
