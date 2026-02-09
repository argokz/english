import os
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # Database: postgresql://USER:PASSWORD@localhost:5440/DATABASE
    database_url: str = "postgresql+asyncpg://postgres:Danil228@localhost:5440/english_app"
    # JWT
    secret_key: str = "change-me-in-production-use-env"
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 60 * 24 * 7  # 7 days
    # Google OAuth2
    google_client_id: str = ""
    google_client_secret: str = ""
    redirect_uri: str = "http://localhost:8000/auth/google/callback"
    frontend_redirect_uri: str = "englishapp://auth"  # Flutter deep link; token in fragment
    # Gemini
    gemini_api_key: str = ""

    class Config:
        env_file = ".env"
        extra = "ignore"


settings = Settings()
# Override database_url from DATABASE_URL if set
if os.getenv("DATABASE_URL"):
    settings.database_url = os.getenv("DATABASE_URL").replace(
        "postgresql://", "postgresql+asyncpg://", 1
    )
if os.getenv("GEMINI_API_KEY"):
    settings.gemini_api_key = os.getenv("GEMINI_API_KEY")
