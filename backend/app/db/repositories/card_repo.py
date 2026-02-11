from datetime import datetime
from uuid import UUID
from sqlalchemy import select, or_, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.card import Card
from app.models.deck import Deck


async def exists_card_in_deck(session: AsyncSession, deck_id: UUID, word: str) -> bool:
    """Проверка без учёта регистра: есть ли уже такое слово в колоде (любая часть речи)."""
    if not (word or "").strip():
        return False
    w = word.strip().lower()
    result = await session.execute(
        select(Card.id).where(Card.deck_id == deck_id, func.lower(Card.word) == w).limit(1)
    )
    return result.scalars().first() is not None


async def exists_card_in_deck_with_pos(
    session: AsyncSession, deck_id: UUID, word: str, part_of_speech: str | None
) -> bool:
    """Есть ли уже карточка с этим словом и этой частью речи в колоде."""
    if not (word or "").strip():
        return False
    w = word.strip().lower()
    q = select(Card.id).where(Card.deck_id == deck_id, func.lower(Card.word) == w)
    if part_of_speech:
        q = q.where(Card.part_of_speech == part_of_speech)
    else:
        q = q.where(Card.part_of_speech.is_(None))
    result = await session.execute(q.limit(1))
    return result.scalars().first() is not None


async def get_cards_by_deck(session: AsyncSession, deck_id: UUID):
    result = await session.execute(select(Card).where(Card.deck_id == deck_id).order_by(Card.created_at.desc()))
    return list(result.scalars().all())


async def get_due_cards(session: AsyncSession, deck_id: UUID, user_id: UUID, now: datetime | None = None):
    from app.models.deck import Deck
    now = now or datetime.utcnow()
    result = await session.execute(
        select(Card)
        .join(Deck, Deck.id == Card.deck_id)
        .where(Deck.id == deck_id, Deck.user_id == user_id, Card.due <= now)
        .order_by(Card.due)
    )
    return list(result.scalars().all())


async def get_card_by_id(session: AsyncSession, card_id: UUID, user_id: UUID) -> Card | None:
    result = await session.execute(
        select(Card).join(Deck, Deck.id == Card.deck_id).where(Card.id == card_id, Deck.user_id == user_id)
    )
    return result.scalars().one_or_none()


async def get_cards_missing_transcription(
    session: AsyncSession, user_id: UUID, deck_id: UUID | None = None, limit: int = 100
) -> list[Card]:
    """Cards that have no transcription or no pronunciation_url, for backfill."""
    q = (
        select(Card)
        .join(Deck, Deck.id == Card.deck_id)
        .where(Deck.user_id == user_id)
        .where(or_(Card.transcription.is_(None), Card.pronunciation_url.is_(None)))
        .order_by(Card.created_at.desc())
        .limit(limit)
    )
    if deck_id is not None:
        q = q.where(Card.deck_id == deck_id)
    result = await session.execute(q)
    return list(result.scalars().all())


async def create_card(
    session: AsyncSession,
    deck_id: UUID,
    word: str,
    translation: str,
    example: str | None = None,
    embedding: list[float] | None = None,
    transcription: str | None = None,
    pronunciation_url: str | None = None,
    part_of_speech: str | None = None,
) -> Card:
    card = Card(
        deck_id=deck_id,
        word=word,
        translation=translation,
        example=example,
        transcription=transcription,
        pronunciation_url=pronunciation_url,
        part_of_speech=part_of_speech,
    )
    if embedding is not None:
        card.embedding = embedding
    session.add(card)
    await session.flush()
    await session.refresh(card)
    return card


async def update_card(session: AsyncSession, card: Card, **kwargs) -> Card:
    for k, v in kwargs.items():
        if hasattr(card, k):
            setattr(card, k, v)
    await session.flush()
    await session.refresh(card)
    return card


async def delete_card(session: AsyncSession, card: Card) -> None:
    await session.delete(card)


async def remove_duplicate_cards_in_deck(session: AsyncSession, deck_id: UUID) -> int:
    """Удаляет дубликаты слов в колоде (без учёта регистра). Оставляет одну карточку на слово (самую старую). Возвращает количество удалённых."""
    cards = await get_cards_by_deck(session, deck_id)
    from collections import defaultdict
    by_word: dict[str, list[Card]] = defaultdict(list)
    for c in cards:
        by_word[(c.word or "").strip().lower()].append(c)
    removed = 0
    for group in by_word.values():
        if len(group) <= 1:
            continue
        group.sort(key=lambda c: c.created_at or datetime.min)
        for c in group[1:]:
            await delete_card(session, c)
            removed += 1
    return removed
