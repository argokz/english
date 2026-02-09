from uuid import UUID
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.deck import Deck


async def get_decks_by_user(session: AsyncSession, user_id: UUID):
    result = await session.execute(select(Deck).where(Deck.user_id == user_id).order_by(Deck.created_at.desc()))
    return list(result.scalars().all())


async def get_deck_by_id(session: AsyncSession, deck_id: UUID, user_id: UUID) -> Deck | None:
    result = await session.execute(select(Deck).where(Deck.id == deck_id, Deck.user_id == user_id))
    return result.scalars().one_or_none()


async def create_deck(session: AsyncSession, user_id: UUID, name: str) -> Deck:
    deck = Deck(user_id=user_id, name=name)
    session.add(deck)
    await session.flush()
    await session.refresh(deck)
    return deck


async def update_deck(session: AsyncSession, deck: Deck, name: str) -> Deck:
    deck.name = name
    await session.flush()
    await session.refresh(deck)
    return deck


async def delete_deck(session: AsyncSession, deck: Deck) -> None:
    await session.delete(deck)
