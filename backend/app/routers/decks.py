from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException, status

from app.dependencies import get_current_user
from app.models.user import User
from app.models.deck import Deck
from app.models.card import Card
from app.schemas.deck import DeckCreate, DeckUpdate, DeckResponse
from app.schemas.card import CardCreate, CardUpdate, CardResponse, ReviewRequest
from app.db.session import get_db
from app.db.repositories import deck_repo, card_repo
from app.services import gemini_service
from sqlalchemy.ext.asyncio import AsyncSession

router = APIRouter()


@router.get("", response_model=list[DeckResponse])
async def list_decks(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    decks = await deck_repo.get_decks_by_user(db, current_user.id)
    return decks


@router.post("", response_model=DeckResponse)
async def create_deck(
    body: DeckCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    deck = await deck_repo.create_deck(db, current_user.id, body.name)
    await db.commit()
    return deck


@router.get("/{deck_id}", response_model=DeckResponse)
async def get_deck(
    deck_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    deck = await deck_repo.get_deck_by_id(db, deck_id, current_user.id)
    if not deck:
        raise HTTPException(status_code=404, detail="Deck not found")
    return deck


@router.patch("/{deck_id}", response_model=DeckResponse)
async def update_deck(
    deck_id: UUID,
    body: DeckUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    deck = await deck_repo.get_deck_by_id(db, deck_id, current_user.id)
    if not deck:
        raise HTTPException(status_code=404, detail="Deck not found")
    deck = await deck_repo.update_deck(db, deck, body.name)
    await db.commit()
    return deck


@router.delete("/{deck_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_deck(
    deck_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    deck = await deck_repo.get_deck_by_id(db, deck_id, current_user.id)
    if not deck:
        raise HTTPException(status_code=404, detail="Deck not found")
    await deck_repo.delete_deck(db, deck)
    await db.commit()


# Cards
@router.get("/{deck_id}/cards", response_model=list[CardResponse])
async def list_cards(
    deck_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    deck = await deck_repo.get_deck_by_id(db, deck_id, current_user.id)
    if not deck:
        raise HTTPException(status_code=404, detail="Deck not found")
    cards = await card_repo.get_cards_by_deck(db, deck_id)
    return cards


@router.post("/{deck_id}/cards", response_model=CardResponse)
async def create_card(
    deck_id: UUID,
    body: CardCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    deck = await deck_repo.get_deck_by_id(db, deck_id, current_user.id)
    if not deck:
        raise HTTPException(status_code=404, detail="Deck not found")
    embedding = gemini_service.get_embedding(f"{body.word}: {body.translation}") if body.word else None
    card = await card_repo.create_card(
        db, deck_id, body.word, body.translation, body.example, 
        embedding=embedding,
        transcription=body.transcription,
        pronunciation_url=body.pronunciation_url,
    )
    await db.commit()
    return card


@router.get("/{deck_id}/due", response_model=list[CardResponse])
async def get_due_cards(
    deck_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    deck = await deck_repo.get_deck_by_id(db, deck_id, current_user.id)
    if not deck:
        raise HTTPException(status_code=404, detail="Deck not found")
    cards = await card_repo.get_due_cards(db, deck_id, current_user.id)
    return cards
