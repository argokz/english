from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import RedirectResponse
from authlib.integrations.httpx_client import AsyncOAuth2Client
from sqlalchemy.ext.asyncio import AsyncSession
from google.oauth2 import id_token as google_id_token
from google.auth.transport import requests as google_requests
import httpx

from app.config import settings
from app.db.session import get_db
from app.db.repositories.user_repo import get_user_by_google_id, create_user
from app.services.auth_service import create_access_token
from app.schemas.auth import TokenResponse, GoogleIdTokenRequest

router = APIRouter()

GOOGLE_AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token"
GOOGLE_USERINFO_URL = "https://www.googleapis.com/oauth2/v3/userinfo"


async def _get_google_user_info(access_token: str) -> dict:
    async with httpx.AsyncClient() as client:
        r = await client.get(
            GOOGLE_USERINFO_URL,
            headers={"Authorization": f"Bearer {access_token}"},
        )
        r.raise_for_status()
        return r.json()


@router.get("/google")
async def google_login(request: Request):
    """Redirect user to Google OAuth2 consent screen."""
    if not settings.google_client_id:
        raise HTTPException(status_code=503, detail="Google OAuth not configured")
    client = AsyncOAuth2Client(
        client_id=settings.google_client_id,
        client_secret=settings.google_client_secret,
        redirect_uri=settings.redirect_uri,
        scope="openid email profile",
    )
    uri, state = client.create_authorization_url(GOOGLE_AUTH_URL, redirect_uri=settings.redirect_uri)
    request.session["oauth_state"] = state
    return RedirectResponse(url=uri)


@router.get("/google/callback")
async def google_callback(
    request: Request,
    code: str | None = None,
    state: str | None = None,
    db: AsyncSession = Depends(get_db),
):
    """Exchange code for tokens, get user info, create/find user, redirect with JWT."""
    if not code:
        raise HTTPException(status_code=400, detail="Missing code")
    saved_state = request.session.get("oauth_state")
    if saved_state and state != saved_state:
        raise HTTPException(status_code=400, detail="Invalid state")
    if not settings.google_client_id:
        raise HTTPException(status_code=503, detail="Google OAuth not configured")
    client = AsyncOAuth2Client(
        client_id=settings.google_client_id,
        client_secret=settings.google_client_secret,
        redirect_uri=settings.redirect_uri,
    )
    redirect_url = str(request.url)
    token = await client.fetch_token(
        GOOGLE_TOKEN_URL,
        authorization_response=redirect_url,
        redirect_uri=settings.redirect_uri,
    )
    if not token or "access_token" not in token:
        raise HTTPException(status_code=400, detail="Failed to get token from Google")
    user_info = await _get_google_user_info(token["access_token"])
    google_id = user_info.get("sub")
    email = user_info.get("email") or ""
    name = user_info.get("name")
    picture_url = user_info.get("picture")
    if not google_id or not email:
        raise HTTPException(status_code=400, detail="Missing user info from Google")

    user = await get_user_by_google_id(db, google_id)
    if not user:
        user = await create_user(db, email=email, google_id=google_id, name=name, picture_url=picture_url)
    await db.commit()

    access_token = create_access_token(data={"sub": str(user.id), "email": user.email})
    response = TokenResponse(
        access_token=access_token,
        user_id=str(user.id),
        email=user.email,
        name=user.name,
    )
    redirect_url = f"{settings.frontend_redirect_uri}#access_token={response.access_token}&user_id={response.user_id}&email={response.email}"
    return RedirectResponse(url=redirect_url)


@router.post("/google/token")
async def google_token(
    body: GoogleIdTokenRequest,
    db: AsyncSession = Depends(get_db),
):
    """Verify Google ID token (from native app sign-in), create/find user, return JWT."""
    if not settings.google_client_id:
        raise HTTPException(status_code=503, detail="Google OAuth not configured")
    try:
        idinfo = google_id_token.verify_oauth2_token(
            body.id_token,
            google_requests.Request(),
            settings.google_client_id,
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=f"Invalid Google ID token: {e}")
    google_id_str = idinfo.get("sub")
    email = idinfo.get("email") or ""
    name = idinfo.get("name")
    picture_url = idinfo.get("picture")
    if not google_id_str or not email:
        raise HTTPException(status_code=400, detail="Missing user info in ID token")

    user = await get_user_by_google_id(db, google_id_str)
    if not user:
        user = await create_user(
            db, email=email, google_id=google_id_str, name=name, picture_url=picture_url
        )
    await db.commit()

    access_token = create_access_token(data={"sub": str(user.id), "email": user.email})
    return TokenResponse(
        access_token=access_token,
        user_id=str(user.id),
        email=user.email,
        name=user.name,
    )


@router.get("/google/callback/json")
async def google_callback_json(
    request: Request,
    code: str | None = None,
    db: AsyncSession = Depends(get_db),
):
    """Same as callback but returns JSON (for clients that can't follow redirect)."""
    if not code:
        raise HTTPException(status_code=400, detail="Missing code")
    if not settings.google_client_id:
        raise HTTPException(status_code=503, detail="Google OAuth not configured")
    client = AsyncOAuth2Client(
        client_id=settings.google_client_id,
        client_secret=settings.google_client_secret,
        redirect_uri=settings.redirect_uri,
    )
    token = await client.fetch_token(
        GOOGLE_TOKEN_URL,
        code=code,
        redirect_uri=settings.redirect_uri,
        grant_type="authorization_code",
    )
    if not token or "access_token" not in token:
        raise HTTPException(status_code=400, detail="Failed to get token from Google")
    user_info = await _get_google_user_info(token["access_token"])
    google_id = user_info.get("sub")
    email = user_info.get("email") or ""
    name = user_info.get("name")
    picture_url = user_info.get("picture")
    if not google_id or not email:
        raise HTTPException(status_code=400, detail="Missing user info from Google")

    user = await get_user_by_google_id(db, google_id)
    if not user:
        user = await create_user(db, email=email, google_id=google_id, name=name, picture_url=picture_url)
    await db.commit()

    access_token = create_access_token(data={"sub": str(user.id), "email": user.email})
    return TokenResponse(
        access_token=access_token,
        user_id=str(user.id),
        email=user.email,
        name=user.name,
    )
