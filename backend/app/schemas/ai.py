from pydantic import BaseModel


class GenerateWordsRequest(BaseModel):
    deck_id: str
    level: str | None = None  # A1, A2, B1, B2, C1
    topic: str | None = None
    count: int = 20


class EnrichWordRequest(BaseModel):
    word: str


class EnrichWordResponse(BaseModel):
    translation: str
    example: str
    transcription: str | None = None
    pronunciation_url: str | None = None


class SimilarWordItem(BaseModel):
    word: str
    translation: str
    example: str | None
    card_id: str


class BackfillTranscriptionsRequest(BaseModel):
    deck_id: str | None = None  # if None, all user's decks
    limit: int = 50


class BackfillTranscriptionsResponse(BaseModel):
    updated: int
