from datetime import datetime
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


class SynonymsResponse(BaseModel):
    synonyms: list[str]
    cards_in_deck: list[SimilarWordItem]  # cards in deck whose word is in synonyms


class SynonymGroupItem(BaseModel):
    words: list[str]
    card_ids: list[str]


class SuggestSynonymGroupsResponse(BaseModel):
    groups: list[SynonymGroupItem]


class ApplySynonymGroupsRequest(BaseModel):
    groups: list[list[str]]  # each inner list is card_ids in one group


class EvaluateWritingRequest(BaseModel):
    text: str
    time_limit_minutes: int | None = None
    time_used_seconds: int | None = None  # фактически затраченное время
    word_limit_min: int | None = None
    word_limit_max: int | None = None
    task_type: str | None = None  # task1, task2, или null


class WritingErrorItem(BaseModel):
    type: str
    original: str
    correction: str
    explanation: str


class EvaluateWritingResponse(BaseModel):
    submission_id: str | None = None
    word_count: int
    time_used_seconds: int | None = None
    evaluation: str
    corrected_text: str
    errors: list[WritingErrorItem]
    recommendations: str


class WritingSubmissionListItem(BaseModel):
    id: str
    word_count: int
    time_used_seconds: int | None
    created_at: datetime
    evaluation_preview: str


class WritingSubmissionResponse(BaseModel):
    id: str
    original_text: str
    word_count: int
    time_used_seconds: int | None
    time_limit_minutes: int | None
    word_limit_min: int | None
    word_limit_max: int | None
    task_type: str | None
    evaluation: str
    corrected_text: str
    errors: list[WritingErrorItem]
    recommendations: str
    created_at: datetime
