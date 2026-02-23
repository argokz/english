import uuid
from sqlalchemy import String, DateTime, ForeignKey, Text, Integer
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship
from datetime import datetime

from app.db.base import Base


class WritingSubmission(Base):
    __tablename__ = "writing_submissions"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    original_text: Mapped[str] = mapped_column(Text, nullable=False)
    word_count: Mapped[int] = mapped_column(Integer, nullable=False)
    time_used_seconds: Mapped[int | None] = mapped_column(Integer, nullable=True)
    time_limit_minutes: Mapped[int | None] = mapped_column(Integer, nullable=True)
    word_limit_min: Mapped[int | None] = mapped_column(Integer, nullable=True)
    word_limit_max: Mapped[int | None] = mapped_column(Integer, nullable=True)
    task_type: Mapped[str | None] = mapped_column(String(32), nullable=True)
    evaluation: Mapped[str] = mapped_column(Text, nullable=False, default="")
    corrected_text: Mapped[str] = mapped_column(Text, nullable=False, default="")
    errors: Mapped[list | None] = mapped_column(JSONB, nullable=True)  # list of {type, original, correction, explanation}
    recommendations: Mapped[str] = mapped_column(Text, nullable=False, default="")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)

    user = relationship("User", back_populates="writing_submissions")
