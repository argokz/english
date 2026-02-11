import logging
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from starlette.middleware.sessions import SessionMiddleware

from app.config import settings
from app.routers import auth, decks, cards, ai
from app.middleware import LoggingMiddleware

# Настройка логирования
log_level = getattr(logging, settings.log_level.upper(), logging.INFO)
logging.basicConfig(
    level=log_level,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)

# Настройка уровней логирования для разных модулей
# Включаем логирование uvicorn для отладки
logging.getLogger("uvicorn.access").setLevel(logging.INFO)  # Включаем для отладки
logging.getLogger("uvicorn").setLevel(logging.INFO)

# SQL логирование (включается через настройку)
if settings.log_sql:
    logging.getLogger("sqlalchemy.engine").setLevel(logging.INFO)
else:
    logging.getLogger("sqlalchemy.engine").setLevel(logging.WARNING)  # SQL запросы только при ошибках

logger = logging.getLogger(__name__)

# Получаем root_path из настроек (для работы за reverse proxy)
root_path = settings.root_path if hasattr(settings, 'root_path') else ""
app = FastAPI(title="English Words API", version="0.1.0", root_path=root_path)

# Middleware для логирования (должен быть первым, чтобы логировать все запросы)
app.add_middleware(LoggingMiddleware)

app.add_middleware(SessionMiddleware, secret_key=settings.secret_key)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Restrict in production (e.g. flutter app origin)
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Глобальный обработчик исключений
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error(
        f"Unhandled exception: {exc.__class__.__name__}: {str(exc)}",
        exc_info=True,
        extra={"path": str(request.url), "method": request.method}
    )
    return JSONResponse(
        status_code=500,
        content={
            "detail": "Internal server error",
            "error": str(exc) if settings.secret_key != "change-me-in-production-use-env" else "Internal server error"
        }
    )

app.include_router(auth.router, prefix="/auth", tags=["auth"])
app.include_router(decks.router, prefix="/decks", tags=["decks"])
app.include_router(cards.router, prefix="/cards", tags=["cards"])
app.include_router(ai.router, prefix="/ai", tags=["ai"])


@app.on_event("startup")
async def startup_event():
    logger.info("🚀 Starting English Words API server...")
    logger.info(f"📊 Environment: {'Development' if settings.secret_key == 'change-me-in-production-use-env' else 'Production'}")
    logger.info(f"🔗 Database: {settings.database_url.split('@')[1] if '@' in settings.database_url else 'configured'}")
    if root_path:
        logger.info(f"🌐 Root path: {root_path} (all routes will be prefixed with this)")
    else:
        logger.info("🌐 Root path: / (no prefix)")
    logger.info("✅ Server started successfully")
    logger.info("📝 Available endpoints:")
    logger.info("   - GET  /health")
    logger.info("   - POST /auth/google/login")
    logger.info("   - GET  /decks, POST /decks/{id}/cards, POST /decks/{id}/backfill-pos, POST /decks/{id}/fetch-examples, ...")
    logger.info("   - GET  /cards")
    logger.info("   - POST /ai/generate-words")


@app.on_event("shutdown")
async def shutdown_event():
    logger.info("🛑 Shutting down server...")


@app.get("/health")
def health():
    return {"status": "ok"}
