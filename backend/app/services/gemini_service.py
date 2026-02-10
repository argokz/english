"""Gemini API: generate word lists, enrich single word. Optional: embeddings for pgvector."""
import os
import re
import json
import logging
from typing import Any

import google.generativeai as genai
from google.api_core import exceptions as google_exceptions
from app.config import settings

genai.configure(api_key=os.environ.get("GEMINI_API_KEY") or settings.gemini_api_key)

logger = logging.getLogger(__name__)


def _get_gemini_models() -> list[str]:
    """Получить список моделей из настроек."""
    models_str = settings.gemini_models or "gemini-3-pro-preview,gemini-3-flash-preview,gemini-2.5-flash,gemini-2.5-flash-lite,gemini-2.5-pro,gemini-2.0-flash"
    models = [m.strip() for m in models_str.split(",") if m.strip()]
    if not models:
        # Fallback на дефолтный список, если что-то пошло не так
        models = [
            "gemini-3-pro-preview",
            "gemini-3-flash-preview",
            "gemini-2.5-flash",
            "gemini-2.5-flash-lite",
            "gemini-2.5-pro",
            "gemini-2.0-flash",
        ]
    return models


# Текущая активная модель (хранится в памяти)
_current_model_index = None


def _get_current_model_index() -> int:
    """Получить индекс текущей модели. Инициализирует с модели из настроек или первой в списке."""
    global _current_model_index
    if _current_model_index is None:
        models = _get_gemini_models()
        # Пытаемся найти модель из настроек в списке
        default_model = settings.gemini_model or "gemini-2.5-flash"
        try:
            _current_model_index = models.index(default_model)
        except ValueError:
            # Модель не найдена в списке, начинаем с первой
            _current_model_index = 0
            logger.warning(f"Модель {default_model} не найдена в списке, используем {models[0]}")
    return _current_model_index


def _switch_to_next_model() -> str:
    """Переключиться на следующую модель в списке. Возвращает имя новой модели."""
    global _current_model_index
    models = _get_gemini_models()
    current_idx = _get_current_model_index()
    next_idx = (current_idx + 1) % len(models)
    _current_model_index = next_idx
    new_model = models[next_idx]
    logger.info(f"Переключение модели: {models[current_idx]} -> {new_model}")
    return new_model


def _get_current_model_name() -> str:
    """Получить имя текущей активной модели."""
    models = _get_gemini_models()
    idx = _get_current_model_index()
    return models[idx]


def _model():
    """Получить объект модели для текущей активной модели."""
    model_name = _get_current_model_name()
    return genai.GenerativeModel(model_name)


def _generate_content_with_fallback(prompt: str) -> str:
    """
    Вызов generate_content с автоматическим переключением модели при исчерпании квоты.
    Все функции, использующие Gemini generate_content, должны вызывать это.
    Общая переменная _current_model_index обновляется здесь — все последующие вызовы используют новую модель.
    """
    models = _get_gemini_models()
    max_attempts = len(models)
    last_error = None
    for attempt in range(max_attempts):
        try:
            current_model_name = _get_current_model_name()
            logger.debug(f"Попытка {attempt + 1}/{max_attempts}: модель {current_model_name}")
            response = _model().generate_content(prompt)
            text = (response.text or "").strip()
            logger.debug(f"Успешно, модель {current_model_name}")
            return text
        except google_exceptions.ResourceExhausted as e:
            last_error = e
            logger.warning(f"Квота исчерпана для {_get_current_model_name()}, переключаемся на следующую модель")
            if attempt < max_attempts - 1:
                _switch_to_next_model()
            else:
                retry_delay = 60
                error_msg = str(e)
                if "retry" in error_msg.lower():
                    import re as re_module
                    delay_match = re_module.search(r"retry in ([\d.]+)s", error_msg, re_module.I)
                    if delay_match:
                        retry_delay = int(float(delay_match.group(1))) + 5
                raise ValueError(
                    f"Превышен лимит запросов для всех моделей Gemini. Попробуйте через {retry_delay} с или перейдите на платный тариф."
                ) from e
    if last_error:
        raise ValueError("Все модели исчерпали квоту") from last_error
    return ""


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

    text = _generate_content_with_fallback(prompt)
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
    logger.info(f"Сгенерировано {len(result)} слов")
    return result[:count]


def enrich_word(word: str) -> dict[str, str]:
    """Get translation, example, and transcription for one word. Returns {translation, example, transcription}."""
    prompt = f"""For the English word "{word}" provide:
1) Russian translation (one word or short phrase)
2) One short example sentence in English using this word.
3) IPA phonetic transcription in square brackets (e.g., [ˈæpl])

Reply in JSON only: {{"translation": "...", "example": "...", "transcription": "..."}}"""

    text = _generate_content_with_fallback(prompt)
    m = re.search(r"\{[^{}]*\"translation\"[^{}]*\"example\"[^{}]*\"transcription\"[^{}]*\}", text)
    if m:
        try:
            result = json.loads(m.group())
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


def get_synonyms(word: str, limit: int = 10) -> list[str]:
    """Return English synonyms (and near-synonyms) for the word. Lowercased, no duplicates. Uses shared model fallback."""
    if not word.strip():
        return []
    prompt = f"""List up to {limit} English synonyms or near-synonyms for the word "{word.strip()}".
Output only the words, one per line, nothing else. Use lowercase. Do not repeat the original word."""
    try:
        text = _generate_content_with_fallback(prompt)
        seen = set()
        result = []
        for line in text.split("\n"):
            w = line.strip().lower()
            if w and w != word.strip().lower() and w not in seen:
                seen.add(w)
                result.append(w)
        return result[:limit]
    except Exception:
        return []


def evaluate_ielts_writing(
    text: str,
    word_limit_min: int | None = None,
    word_limit_max: int | None = None,
    task_type: str | None = None,
) -> dict:
    """
    Оценка текста для IELTS Writing: общая оценка, исправленный текст, список ошибок, рекомендации.
    Возвращает dict: evaluation, corrected_text, errors (list of {type, original, correction, explanation}), recommendations.
    """
    if not text or not text.strip():
        return {
            "evaluation": "",
            "corrected_text": "",
            "errors": [],
            "recommendations": "Введите текст для проверки.",
        }
    limits = ""
    if word_limit_min is not None or word_limit_max is not None:
        limits = f" Target word count: min {word_limit_min or 0}, max {word_limit_max or 'none'}."
    task = f" Task type: {task_type}." if task_type else ""
    prompt = f"""You are an IELTS Writing examiner. Analyze the following English text{task}.{limits}

TEXT:
---
{text.strip()}
---

Respond in JSON only with this exact structure (use Russian for evaluation, errors explanations, and recommendations):
{{
  "evaluation": "Краткая общая оценка текста: соответствие заданию, связность, грамматика, лексика. 2-4 предложения.",
  "corrected_text": "Полный текст с исправленными грамматическими и орфографическими ошибками. Сохраняйте структуру и смысл автора.",
  "errors": [
    {{ "type": "grammar|spelling|punctuation|vocabulary|style", "original": "фраза с ошибкой", "correction": "исправленный вариант", "explanation": "краткое объяснение на русском" }}
  ],
  "recommendations": "3-5 конкретных рекомендаций по улучшению (на русском)."
}}
If there are no errors, return "errors": [].
Output only valid JSON, no markdown or extra text."""

    try:
        raw = _generate_content_with_fallback(prompt)
        # Убрать markdown-обёртку если есть
        raw = raw.strip()
        if raw.startswith("```"):
            raw = raw.split("\n", 1)[-1]
        if raw.endswith("```"):
            raw = raw.rsplit("```", 1)[0]
        raw = raw.strip()
        data = json.loads(raw)
        return {
            "evaluation": data.get("evaluation", ""),
            "corrected_text": data.get("corrected_text", ""),
            "errors": data.get("errors") if isinstance(data.get("errors"), list) else [],
            "recommendations": data.get("recommendations", ""),
        }
    except (json.JSONDecodeError, ValueError) as e:
        logger.warning(f"evaluate_ielts_writing parse error: {e}")
        return {
            "evaluation": "Не удалось разобрать ответ. Попробуйте ещё раз.",
            "corrected_text": text,
            "errors": [],
            "recommendations": "",
        }


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
