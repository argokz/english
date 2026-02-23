from uuid import UUID
from sqlalchemy import select
from sqlalchemy.orm import selectinload
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Optional, List

from app.models.youtube_video import YouTubeVideo
from app.models.user_youtube_video import UserYouTubeVideo

async def get_video_by_youtube_id(session: AsyncSession, video_id: str) -> Optional[YouTubeVideo]:
    result = await session.execute(select(YouTubeVideo).where(YouTubeVideo.video_id == video_id))
    return result.scalars().first()

async def get_video_by_id(session: AsyncSession, id: UUID) -> Optional[YouTubeVideo]:
    result = await session.execute(select(YouTubeVideo).where(YouTubeVideo.id == id))
    return result.scalars().first()

async def create_video(session: AsyncSession, video_id: str, url: str, transcription: str, translation: str, summary: str) -> YouTubeVideo:
    video = YouTubeVideo(
        video_id=video_id,
        url=url,
        transcription=transcription,
        translation=translation,
        summary=summary
    )
    session.add(video)
    await session.flush()
    await session.refresh(video)
    return video

async def add_to_user_history(session: AsyncSession, user_id: UUID, video_id: UUID) -> UserYouTubeVideo:
    # First, check if it already exists to avoid duplicates
    existing = await session.execute(
        select(UserYouTubeVideo).where(
            UserYouTubeVideo.user_id == user_id,
            UserYouTubeVideo.video_id == video_id
        )
    )
    history_entry = existing.scalars().first()
    
    if not history_entry:
        history_entry = UserYouTubeVideo(user_id=user_id, video_id=video_id)
        session.add(history_entry)
        await session.flush()
        await session.refresh(history_entry)
    return history_entry

async def get_user_history(session: AsyncSession, user_id: UUID, limit: int = 50, offset: int = 0) -> List[UserYouTubeVideo]:
    result = await session.execute(
        select(UserYouTubeVideo)
        .where(UserYouTubeVideo.user_id == user_id)
        .options(selectinload(UserYouTubeVideo.video))
        .order_by(UserYouTubeVideo.viewed_at.desc())
        .limit(limit)
        .offset(offset)
    )
    return list(result.scalars().all())
