import uuid
from sqlalchemy import Column, String, Text, DateTime, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from app.db.base import Base

class YouTubeVideo(Base):
    __tablename__ = "youtube_videos"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, index=True)
    video_id = Column(String, unique=True, index=True, nullable=False)
    url = Column(String, nullable=False)
    transcription = Column(Text, nullable=False)
    translation = Column(Text, nullable=False)
    summary = Column(Text, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user_histories = relationship("UserYouTubeVideo", back_populates="video", cascade="all, delete-orphan")
