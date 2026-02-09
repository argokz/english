"""Card PATCH/DELETE and POST review. Card id is global (user checked via deck)."""
from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.dependencies import get_current_user
from app.models.user import User
from app.schemas.card import CardUpdate, CardResponse, ReviewRequest
from app.db.session import get_db
from app.db.repositories import card_repo
from app.services.fsrs_service import review_card as fsrs_review

router = APIRouter()


@router.patch("/{card_id}", response_model=CardResponse)
async def update_card(
    card_id: UUID,
    body: CardUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    card = await card_repo.get_card_by_id(db, card_id, current_user.id)
    if not card:
        raise HTTPException(status_code=404, detail="Card not found")
    updates = body.model_dump(exclude_unset=True)
    if updates:
        card = await card_repo.update_card(db, card, **updates)
    await db.commit()
    return card


@router.delete("/{card_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_card(
    card_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    card = await card_repo.get_card_by_id(db, card_id, current_user.id)
    if not card:
        raise HTTPException(status_code=404, detail="Card not found")
    await card_repo.delete_card(db, card)
    await db.commit()


@router.post("/{card_id}/review", response_model=CardResponse)
async def review_card_endpoint(
    card_id: UUID,
    body: ReviewRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if body.rating not in (1, 2, 3, 4):
        raise HTTPException(status_code=400, detail="rating must be 1, 2, 3, or 4")
    card = await card_repo.get_card_by_id(db, card_id, current_user.id)
    if not card:
        raise HTTPException(status_code=404, detail="Card not found")
    new_fsrs_data, new_due = fsrs_review(card.fsrs_data, body.rating)
    card = await card_repo.update_card(
        db, card, fsrs_data=new_fsrs_data, due=new_due
    )
    await db.commit()
    return card
