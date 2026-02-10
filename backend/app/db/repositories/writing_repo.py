from uuid import UUID
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.writing_submission import WritingSubmission


async def create_writing_submission(
    session: AsyncSession,
    user_id: UUID,
    original_text: str,
    word_count: int,
    evaluation: str,
    corrected_text: str,
    recommendations: str,
    time_used_seconds: int | None = None,
    time_limit_minutes: int | None = None,
    word_limit_min: int | None = None,
    word_limit_max: int | None = None,
    task_type: str | None = None,
    errors: list | None = None,
) -> WritingSubmission:
    sub = WritingSubmission(
        user_id=user_id,
        original_text=original_text,
        word_count=word_count,
        time_used_seconds=time_used_seconds,
        time_limit_minutes=time_limit_minutes,
        word_limit_min=word_limit_min,
        word_limit_max=word_limit_max,
        task_type=task_type,
        evaluation=evaluation,
        corrected_text=corrected_text,
        errors=errors,
        recommendations=recommendations,
    )
    session.add(sub)
    await session.flush()
    await session.refresh(sub)
    return sub


async def get_writing_submissions_by_user(
    session: AsyncSession, user_id: UUID, limit: int = 50, offset: int = 0
) -> list[WritingSubmission]:
    result = await session.execute(
        select(WritingSubmission)
        .where(WritingSubmission.user_id == user_id)
        .order_by(WritingSubmission.created_at.desc())
        .limit(limit)
        .offset(offset)
    )
    return list(result.scalars().all())


async def get_writing_submission_by_id(
    session: AsyncSession, submission_id: UUID, user_id: UUID
) -> WritingSubmission | None:
    result = await session.execute(
        select(WritingSubmission).where(
            WritingSubmission.id == submission_id,
            WritingSubmission.user_id == user_id,
        )
    )
    return result.scalars().one_or_none()
