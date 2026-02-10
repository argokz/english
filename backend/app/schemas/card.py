from datetime import datetime
from uuid import UUID
from pydantic import BaseModel


class CardCreate(BaseModel):
    word: str
    translation: str
    example: str | None = None
    transcription: str | None = None
    pronunciation_url: str | None = None


class CardUpdate(BaseModel):
    word: str | None = None
    translation: str | None = None
    example: str | None = None
    transcription: str | None = None
    pronunciation_url: str | None = None


class CardResponse(BaseModel):
    id: UUID
    deck_id: UUID
    word: str
    translation: str
    example: str | None
    transcription: str | None = None
    pronunciation_url: str | None = None
    created_at: datetime
    state: str
    due: datetime
    synonym_group_id: UUID | None = None

    class Config:
        from_attributes = True


class ReviewRequest(BaseModel):
    rating: int  # 1=Again, 2=Hard, 3=Good, 4=Easy
