from uuid import UUID
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User


async def get_user_by_google_id(session: AsyncSession, google_id: str) -> User | None:
    result = await session.execute(select(User).where(User.google_id == google_id))
    return result.scalars().one_or_none()


async def get_user_by_id(session: AsyncSession, user_id: UUID) -> User | None:
    result = await session.execute(select(User).where(User.id == user_id))
    return result.scalars().one_or_none()


async def create_user(
    session: AsyncSession,
    email: str,
    google_id: str,
    name: str | None = None,
    picture_url: str | None = None,
) -> User:
    user = User(email=email, google_id=google_id, name=name, picture_url=picture_url)
    session.add(user)
    await session.flush()
    await session.refresh(user)
    return user
