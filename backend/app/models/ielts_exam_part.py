import uuid
from sqlalchemy import Column, Integer, ForeignKey, DateTime, func
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import relationship

from app.db.base import Base

class IeltsExamPart(Base):
    __tablename__ = "ielts_exam_parts"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, index=True)
    video_id = Column(UUID(as_uuid=True), ForeignKey("youtube_videos.id", ondelete="CASCADE"), nullable=False, index=True)
    part_number = Column(Integer, nullable=False, index=True)
    questions = Column(JSONB, nullable=False)  # List of questions with answers and explanations
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    video = relationship("YouTubeVideo", back_populates="exam_parts")
