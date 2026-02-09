from datetime import datetime
from uuid import UUID
from pydantic import BaseModel


class DeckCreate(BaseModel):
    name: str


class DeckUpdate(BaseModel):
    name: str


class DeckResponse(BaseModel):
    id: UUID
    name: str
    created_at: datetime

    class Config:
        from_attributes = True
