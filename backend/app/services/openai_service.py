"""OpenAI API: генерация текста с переключением между моделями при ошибках."""
import logging
from openai import OpenAI
from app.config import settings

logger = logging.getLogger(__name__)

_client: OpenAI | None = None
_current_model_index: int | None = None


def _get_client() -> OpenAI | None:
    global _client
    key = getattr(settings, "openai_api_key", None) or ""
    if not key or not key.strip():
        return None
    if _client is None:
        _client = OpenAI(api_key=key.strip())
    return _client


def _get_openai_models() -> list[str]:
    models_str = getattr(settings, "openai_models", None) or "gpt-4o,gpt-4o-mini,gpt-4-turbo,gpt-3.5-turbo"
    models = [m.strip() for m in models_str.split(",") if m.strip()]
    return models or ["gpt-4o", "gpt-4o-mini"]


def _get_current_openai_index() -> int:
    global _current_model_index
    models = _get_openai_models()
    if _current_model_index is None:
        _current_model_index = 0
    if _current_model_index >= len(models):
        _current_model_index = 0
    return _current_model_index


def _switch_to_next_openai_model() -> str:
    global _current_model_index
    models = _get_openai_models()
    idx = _get_current_openai_index()
    next_idx = (idx + 1) % len(models)
    _current_model_index = next_idx
    new_model = models[next_idx]
    logger.info("Переключение OpenAI: %s -> %s", models[idx], new_model)
    return new_model


def generate_content(prompt: str) -> str:
    """
    Генерация ответа через OpenAI. Перебор моделей из OPENAI_MODELS при ошибке/квоте.
    При недоступности всех моделей выбрасывает ValueError.
    """
    client = _get_client()
    if client is None:
        raise ValueError("OPENAI_API_KEY не задан. Укажите ключ в .env или переменной окружения.")

    models = _get_openai_models()
    last_error = None
    for attempt in range(len(models)):
        idx = _get_current_openai_index()
        model_name = models[idx]
        try:
            logger.debug("OpenAI попытка %s/%s: модель %s", attempt + 1, len(models), model_name)
            response = client.chat.completions.create(
                model=model_name,
                messages=[{"role": "user", "content": prompt}],
            )
            text = (response.choices[0].message.content or "").strip()
            if text:
                logger.debug("OpenAI успешно, модель %s", model_name)
                return text
        except Exception as e:
            last_error = e
            logger.warning("OpenAI ошибка для %s: %s", model_name, e)
            if attempt < len(models) - 1:
                _switch_to_next_openai_model()
            else:
                raise ValueError(
                    f"Все модели OpenAI недоступны. Последняя ошибка: {e}"
                ) from e
    if last_error:
        raise ValueError(f"OpenAI: {last_error}") from last_error
    return ""
