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


def _generate_content_gemini_only(prompt: str) -> str:
    """
    Только Gemini: перебор моделей при исчерпании квоты/ошибке. При неудаче по всем моделям — ValueError.
    """
    models = _get_gemini_models()
    max_attempts = len(models)
    last_error = None
    for attempt in range(max_attempts):
        try:
            current_model_name = _get_current_model_name()
            logger.debug("Gemini попытка %s/%s: модель %s", attempt + 1, max_attempts, current_model_name)
            response = _model().generate_content(prompt)
            text = (response.text or "").strip()
            logger.debug("Gemini успешно, модель %s", current_model_name)
            return text
        except google_exceptions.ResourceExhausted as e:
            last_error = e
            logger.warning("Квота исчерпана для %s, переключаемся на следующую модель", _get_current_model_name())
            if attempt < max_attempts - 1:
                _switch_to_next_model()
            else:
                retry_delay = 60
                error_msg = str(e)
                if "retry" in error_msg.lower():
                    delay_match = re.search(r"retry in ([\d.]+)s", error_msg, re.I)
                    if delay_match:
                        retry_delay = int(float(delay_match.group(1))) + 5
                raise ValueError(
                    f"Превышен лимит запросов для всех моделей Gemini. Попробуйте через {retry_delay} с."
                ) from e
        except Exception as e:
            last_error = e
            logger.warning("Gemini ошибка для %s: %s", _get_current_model_name(), e)
            if attempt < max_attempts - 1:
                _switch_to_next_model()
            else:
                raise ValueError(f"Все модели Gemini недоступны: {e}") from e
    if last_error:
        raise ValueError("Все модели Gemini исчерпали квоту") from last_error
    return ""


def _generate_content_with_fallback(prompt: str) -> str:
    """
    Единая точка генерации: приоритет из AI_PRIORITY (gpt | gemini).
    Если все модели приоритетного провайдера недоступны — переключение на второй провайдер (GPT ↔ Gemini).
    """
    priority = (getattr(settings, "ai_priority", None) or "gemini").strip().lower()
    if priority == "gpt":
        try:
            from app.services import openai_service
            return openai_service.generate_content(prompt)
        except ValueError as e1:
            logger.warning("OpenAI недоступен (%s), пробуем Gemini", e1)
        try:
            return _generate_content_gemini_only(prompt)
        except ValueError as e2:
            raise ValueError(
                f"Сначала все модели GPT недоступны ({e1}). Затем все модели Gemini тоже недоступны ({e2})."
            ) from e2
    # priority == "gemini" или любое другое значение
    try:
        return _generate_content_gemini_only(prompt)
    except ValueError as e1:
        logger.warning("Gemini недоступен (%s), пробуем OpenAI", e1)
        try:
            from app.services import openai_service
            return openai_service.generate_content(prompt)
        except ValueError as e2:
            raise ValueError(
                f"Сначала все модели Gemini недоступны ({e1}). Затем все модели GPT тоже недоступны ({e2})."
            ) from e2


def generate_word_list(level: str | None = None, topic: str | None = None, count: int = 20) -> list[dict[str, str]]:
    """Generate list of words with translation, example, and IPA. Include variety: different parts of speech (noun, verb, adj, adv) and some synonym pairs."""
    if not level and not topic:
        level = "A1"
    prompt = f"""Generate {count} frequent English words for learners.
{"Use CEFR level: " + level + "." if level else ""}
{"Use topic/theme: " + topic + "." if topic else ""}
Include a mix: nouns, verbs, adjectives, adverbs, and where useful 1-2 pairs of synonyms (e.g. big/large).
For each word: 1) English word, 2) Russian translation, 3) one short example in English, 4) IPA (e.g. ˈæpl).
Output: one line per word, pipe-separated: word | translation | example | transcription
Example: apple | яблоко | I eat an apple every day. | ˈæpl
Do not add numbering. Only lines: word | translation | example | transcription"""

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
    data = enrich_word_with_pos(word)
    if data.get("senses"):
        first = data["senses"][0]
        return {
            "translation": first.get("translation", ""),
            "example": first.get("example", ""),
            "transcription": data.get("transcription") or "",
        }
    return {"translation": "", "example": "", "transcription": ""}


# Кэш обогащения по слову (экономия токенов при повторных запросах)
_enrich_cache: dict[str, tuple[dict[str, Any], float]] = {}
_ENRICH_CACHE_TTL = 300  # секунд
_ENRICH_CACHE_MAX = 200


def _parse_enrich_response(text: str, word: str) -> dict[str, Any]:
    """Парсинг JSON-ответа enrich: transcription + senses."""
    m = re.search(r"\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\"senses\"[^{}]*(?:\[.*?\])[^{}]*\}", text, re.DOTALL)
    if not m:
        m = re.search(r"\{.*\"senses\".*\}", text, re.DOTALL)
    if not m:
        m = re.search(r"\{[^{}]*\"transcription\"[^{}]*\}", text)
    if not m:
        return {"transcription": None, "senses": []}
    try:
        raw = re.sub(r",\s*([}\]])", r"\1", m.group(0))
        result = json.loads(raw)
        transcription = (result.get("transcription") or "").strip().strip("[]") or None
        senses = result.get("senses") or []
        normalized = []
        for s in senses:
            if not isinstance(s, dict):
                continue
            pos = (s.get("part_of_speech") or "").strip().lower()
            if pos not in ("noun", "verb", "adjective", "adverb"):
                continue
            normalized.append({
                "part_of_speech": pos,
                "translation": (s.get("translation") or "").strip(),
                "example": (s.get("example") or "").strip(),
            })
        if not normalized:
            trans = (result.get("translation") or "").strip()
            ex = (result.get("example") or "").strip()
            if trans or ex:
                normalized = [{"part_of_speech": "noun", "translation": trans, "example": ex}]
        return {"transcription": transcription, "senses": normalized}
    except json.JSONDecodeError:
        return {"transcription": None, "senses": []}


def _parse_enrich_batch_response(text: str, words: list[str]) -> list[dict[str, Any]]:
    """Парсинг ответа батч enrich: массив объектов {transcription, senses} в том же порядке, что и words."""
    result: list[dict[str, Any]] = []
    # Ищем JSON-массив [...]
    m = re.search(r"\[\s*\{", text)
    if not m:
        # Один объект — считаем ответом для одного слова
        single = _parse_enrich_response(text, words[0] if words else "")
        return [single] + [{"transcription": None, "senses": []} for _ in range(len(words) - 1)]
    try:
        start = text.index("[")
        depth = 0
        end = start
        for i, c in enumerate(text[start:], start):
            if c == "[":
                depth += 1
            elif c == "]":
                depth -= 1
                if depth == 0:
                    end = i
                    break
        raw = text[start : end + 1]
        raw = re.sub(r",\s*([}\]])", r"\1", raw)
        arr = json.loads(raw)
        for i, item in enumerate(arr):
            if not isinstance(item, dict):
                result.append({"transcription": None, "senses": []})
                continue
            senses = item.get("senses") or []
            normalized = []
            for s in senses:
                if not isinstance(s, dict):
                    continue
                pos = (s.get("part_of_speech") or "").strip().lower()
                if pos not in ("noun", "verb", "adjective", "adverb"):
                    continue
                normalized.append({
                    "part_of_speech": pos,
                    "translation": (s.get("translation") or "").strip(),
                    "example": (s.get("example") or "").strip(),
                })
            if not normalized and (item.get("translation") or item.get("example")):
                normalized = [{
                    "part_of_speech": "noun",
                    "translation": (item.get("translation") or "").strip(),
                    "example": (item.get("example") or "").strip(),
                }]
            transcription = (item.get("transcription") or "").strip().strip("[]") or None
            result.append({"transcription": transcription, "senses": normalized})
        while len(result) < len(words):
            result.append({"transcription": None, "senses": []})
        return result[: len(words)]
    except (json.JSONDecodeError, ValueError):
        return [_parse_enrich_response(text, w) if i == 0 else {"transcription": None, "senses": []} for i, w in enumerate(words)]


BATCH_ENRICH_SIZE = 10


def enrich_words_with_pos_batch(words: list[str]) -> list[dict[str, Any]]:
    """Обогатить до 10 слов одним запросом: для каждого слово — transcription и senses (части речи). Порядок как у words."""
    words = [(w or "").strip() for w in words if (w or "").strip()][:BATCH_ENRICH_SIZE]
    if not words:
        return []
    import time
    now = time.time()
    # Проверяем кэш: все ли уже есть
    to_fetch: list[tuple[int, str]] = []
    result: list[dict[str, Any]] = [{"transcription": None, "senses": []} for _ in words]
    for i, w in enumerate(words):
        key = w.lower()
        if key in _enrich_cache:
            data, ts = _enrich_cache[key]
            if now - ts < _ENRICH_CACHE_TTL:
                result[i] = data
                continue
            del _enrich_cache[key]
        to_fetch.append((i, w))
    if not to_fetch:
        return result
    fetch_words = [w for _, w in to_fetch]
    word_list = ", ".join(f'"{w}"' for w in fetch_words)
    prompt = f'''For each English word return one JSON object with "transcription" (IPA) and "senses" (parts of speech). Words: {word_list}.
senses: array of {{"part_of_speech": "noun|verb|adjective|adverb", "translation": "рус", "example": "short EN sentence"}}. Only applicable POS.
Output: a single JSON array of {len(fetch_words)} objects, in the same order as the words above. No other text.'''
    try:
        text = _generate_content_with_fallback(prompt)
        batch_results = _parse_enrich_batch_response(text, fetch_words)
        for (idx, w), data in zip(to_fetch, batch_results):
            result[idx] = data
            key = w.lower()
            if len(_enrich_cache) >= _ENRICH_CACHE_MAX:
                for k in sorted(_enrich_cache.keys(), key=lambda x: _enrich_cache[x][1])[: _ENRICH_CACHE_MAX // 2]:
                    del _enrich_cache[k]
            _enrich_cache[key] = (data, time.time())
    except Exception:
        for idx, w in to_fetch:
            result[idx] = {"transcription": None, "senses": []}
    return result


def enrich_word_with_pos(word: str) -> dict[str, Any]:
    """Все части речи для слова: senses (part_of_speech, translation, example), transcription. С кэшем."""
    w = (word or "").strip()
    if not w:
        return {"transcription": None, "senses": []}
    key = w.lower()
    import time
    now = time.time()
    if key in _enrich_cache:
        data, ts = _enrich_cache[key]
        if now - ts < _ENRICH_CACHE_TTL:
            return data
        del _enrich_cache[key]
    if len(_enrich_cache) >= _ENRICH_CACHE_MAX:
        # Удалить самые старые
        for k in sorted(_enrich_cache.keys(), key=lambda x: _enrich_cache[x][1])[: _ENRICH_CACHE_MAX // 2]:
            del _enrich_cache[k]

    prompt = f'''Word "{w}". JSON: {{"transcription": "[IPA]", "senses": [{{"part_of_speech": "noun|verb|adjective|adverb", "translation": "рус", "example": "short EN sentence"}}]}}. Only applicable POS.'''
    text = _generate_content_with_fallback(prompt)
    data = _parse_enrich_response(text, w)
    _enrich_cache[key] = (data, now)
    return data


def translate(text: str, source_lang: str, target_lang: str) -> str:
    """Translate text between Russian and English. source_lang/target_lang: 'ru' or 'en'."""
    if not (text or "").strip():
        return ""
    src = "Russian" if source_lang.strip().lower() == "ru" else "English"
    tgt = "Russian" if target_lang.strip().lower() == "ru" else "English"
    prompt = f"""Translate the following text from {src} to {tgt}. Output only the translation, no explanations.
Text: {text.strip()}
Translation:"""
    try:
        result = _generate_content_with_fallback(prompt)
        return (result or "").strip()
    except Exception:
        return ""


def get_examples_for_card(word: str, translation: str, part_of_speech: str | None) -> list[str]:
    """Сгенерировать 3–5 примеров предложений для слова в данном значении (частое употребление)."""
    if not (word or "").strip():
        return []
    pos = (part_of_speech or "").strip().lower() or "any"
    prompt = f"""English word "{word.strip()}" (Russian: {translation.strip()}, part of speech: {pos}).
Give 3 to 5 short example sentences in English where this word is used in this meaning. Common usage only.
Output: one sentence per line, no numbering, no extra text."""
    try:
        text = _generate_content_with_fallback(prompt)
        lines = [s.strip() for s in (text or "").split("\n") if s.strip() and not s.strip()[0].isdigit()]
        return lines[:5]
    except Exception:
        return []


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


BATCH_SYNONYM_SIZE = 10


def get_synonyms_batch(words: list[str], limit: int = 12) -> list[list[str]]:
    """Для каждого слова из списка (до 10) вернуть список синонимов одним запросом. Порядок как у words."""
    words = [(w or "").strip() for w in words if (w or "").strip()][:BATCH_SYNONYM_SIZE]
    if not words:
        return []
    word_list = ", ".join(f'"{w}"' for w in words)
    prompt = f"""For each of these English words list up to {limit} synonyms or near-synonyms (lowercase, comma-separated). Do not repeat the word itself.
Output exactly one line per word in the same order. Format: word: syn1, syn2, syn3
Words: {word_list}"""
    try:
        text = _generate_content_with_fallback(prompt)
        lines = [s.strip() for s in (text or "").split("\n") if s.strip()]
        result: list[list[str]] = []
        for i, w in enumerate(words):
            syns: list[str] = []
            w_lower = w.lower()
            if i < len(lines):
                line = lines[i]
                rest = line
                for sep in (":", " - ", "-"):
                    if sep in line:
                        idx = line.find(sep)
                        rest = line[idx + len(sep) :].strip()
                        break
                for part in rest.replace(";", ",").split(","):
                    s = part.strip().lower().strip(".")
                    if s and s != w_lower and s not in syns:
                        syns.append(s)
            result.append(syns[:limit])
        while len(result) < len(words):
            result.append([])
        return result[: len(words)]
    except Exception:
        return [[] for _ in words]


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
  "band_score": 6.5,
  "evaluation": "Краткая общая оценка текста: соответствие заданию, связность, грамматика, лексика. 2-4 предложения.",
  "corrected_text": "Полный текст с исправленными грамматическими и орфографическими ошибками. Сохраняйте структуру и смысл автора.",
  "errors": [
    {{ "type": "grammar|spelling|punctuation|vocabulary|style", "original": "фраза с ошибкой", "correction": "исправленный вариант", "explanation": "краткое объяснение на русском" }}
  ],
  "recommendations": "3-5 конкретных рекомендаций по улучшению (на русском)."
}}
band_score: number from 0 to 9 in steps of 0.5 (IELTS Writing band). If there are no errors, return "errors": [].
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
        band = data.get("band_score")
        if band is not None:
            try:
                band = float(band)
                if band < 0 or band > 9:
                    band = None
            except (TypeError, ValueError):
                band = None
        return {
            "band_score": band,
            "evaluation": data.get("evaluation", ""),
            "corrected_text": data.get("corrected_text", ""),
            "errors": data.get("errors") if isinstance(data.get("errors"), list) else [],
            "recommendations": data.get("recommendations", ""),
        }
    except (json.JSONDecodeError, ValueError) as e:
        logger.warning(f"evaluate_ielts_writing parse error: {e}")
        return {
            "band_score": None,
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
