from datetime import datetime
from uuid import UUID
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.card import Card


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
    from app.models.deck import Deck
    result = await session.execute(
        select(Card).join(Deck, Deck.id == Card.deck_id).where(Card.id == card_id, Deck.user_id == user_id)
    )
    return result.scalars().one_or_none()


async def create_card(
    session: AsyncSession,
    deck_id: UUID,
    word: str,
    translation: str,
    example: str | None = None,
    embedding: list[float] | None = None,
    transcription: str | None = None,
    pronunciation_url: str | None = None,
) -> Card:
    card = Card(
        deck_id=deck_id, 
        word=word, 
        translation=translation, 
        example=example,
        transcription=transcription,
        pronunciation_url=pronunciation_url,
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
