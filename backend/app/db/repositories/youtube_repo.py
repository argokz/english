from uuid import UUID
from sqlalchemy import select
from sqlalchemy.orm import selectinload
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Optional, List

from app.models.youtube_video import YouTubeVideo
from app.models.user_youtube_video import UserYouTubeVideo
from app.models.ielts_exam_part import IeltsExamPart

async def get_video_by_youtube_id(session: AsyncSession, video_id: str) -> Optional[YouTubeVideo]:
    result = await session.execute(select(YouTubeVideo).where(YouTubeVideo.video_id == video_id))
    return result.scalars().first()

async def get_exam_part_by_video_id(session: AsyncSession, video_id: UUID, part_number: int) -> Optional[IeltsExamPart]:
    result = await session.execute(
        select(IeltsExamPart).where(IeltsExamPart.video_id == video_id, IeltsExamPart.part_number == part_number)
    )
    return result.scalars().first()

async def get_random_exam_part(session: AsyncSession, part_number: int) -> Optional[IeltsExamPart]:
    from sqlalchemy import func
    result = await session.execute(
        select(IeltsExamPart)
        .where(IeltsExamPart.part_number == part_number)
        .order_by(func.random())
        .limit(1)
        .options(selectinload(IeltsExamPart.video))
    )
    return result.scalars().first()

async def create_exam_part(session: AsyncSession, video_id: UUID, part_number: int, questions: list) -> IeltsExamPart:
    exam_part = IeltsExamPart(
        video_id=video_id,
        part_number=part_number,
        questions=questions
    )
    session.add(exam_part)
    await session.flush()
    await session.refresh(exam_part)
    return exam_part

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
