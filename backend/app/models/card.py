import uuid
from sqlalchemy import String, DateTime, ForeignKey, Text
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship
from datetime import datetime
import enum
from pgvector.sqlalchemy import Vector

from app.db.base import Base


class CardState(str, enum.Enum):
    learning = "learning"
    review = "review"
    relearning = "relearning"


class Card(Base):
    __tablename__ = "cards"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    deck_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("decks.id", ondelete="CASCADE"), nullable=False)
    word: Mapped[str] = mapped_column(String(255), nullable=False)
    translation: Mapped[str] = mapped_column(String(512), nullable=False)
    example: Mapped[str | None] = mapped_column(Text, nullable=True)
    transcription: Mapped[str | None] = mapped_column(String(100), nullable=True)  # IPA transcription
    pronunciation_url: Mapped[str | None] = mapped_column(String(512), nullable=True)  # URL to audio file
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)

    state: Mapped[str] = mapped_column(String(32), nullable=False, default=CardState.learning.value)
    due: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=datetime.utcnow)
    fsrs_data: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    embedding: Mapped[list | None] = mapped_column(Vector(768), nullable=True)

    deck = relationship("Deck", back_populates="cards")
    review_logs = relationship("ReviewLog", back_populates="card", cascade="all, delete-orphan")
