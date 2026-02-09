from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.sessions import SessionMiddleware

from app.config import settings
from app.routers import auth, decks, cards, ai

app = FastAPI(title="English Words API", version="0.1.0")

app.add_middleware(SessionMiddleware, secret_key=settings.secret_key)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Restrict in production (e.g. flutter app origin)
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router, prefix="/auth", tags=["auth"])
app.include_router(decks.router, prefix="/decks", tags=["decks"])
app.include_router(cards.router, prefix="/cards", tags=["cards"])
app.include_router(ai.router, prefix="/ai", tags=["ai"])


@app.get("/health")
def health():
    return {"status": "ok"}
