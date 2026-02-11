from uuid import UUID, uuid4
from fastapi import APIRouter, Depends, HTTPException, status

from app.dependencies import get_current_user
from app.models.user import User
from app.models.deck import Deck
from app.models.card import Card
from app.schemas.deck import DeckCreate, DeckUpdate, DeckResponse
from app.schemas.card import CardCreate, CardUpdate, CardResponse, ReviewRequest
from app.schemas.ai import ApplySynonymGroupsRequest, BackfillPosRequest, BackfillPosResponse
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
    if await card_repo.exists_card_in_deck_with_pos(db, deck_id, body.word, body.part_of_speech):
        raise HTTPException(status_code=409, detail="Слово уже есть в колоде (с этой частью речи)")
    embedding = gemini_service.get_embedding(f"{body.word}: {body.translation}") if body.word else None
    card = await card_repo.create_card(
        db, deck_id, body.word, body.translation, body.example,
        embedding=embedding,
        transcription=body.transcription,
        pronunciation_url=body.pronunciation_url,
        part_of_speech=body.part_of_speech,
    )
    await db.commit()
    return card


@router.post("/{deck_id}/cards/{card_id}/fetch-examples", response_model=CardResponse)
async def fetch_card_examples(
    deck_id: UUID,
    card_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Запросить примеры предложений для карточки (по переводу и частому употреблению), сохранить в БД."""
    deck = await deck_repo.get_deck_by_id(db, deck_id, current_user.id)
    if not deck:
        raise HTTPException(status_code=404, detail="Deck not found")
    card = await card_repo.get_card_by_id(db, card_id, current_user.id)
    if not card or card.deck_id != deck_id:
        raise HTTPException(status_code=404, detail="Card not found")
    try:
        examples = gemini_service.get_examples_for_card(
            card.word or "",
            card.translation or "",
            card.part_of_speech,
        )
    except ValueError as e:
        raise HTTPException(status_code=429, detail=str(e))
    await card_repo.update_card(db, card, examples=examples if examples else None)
    await db.commit()
    await db.refresh(card)
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


@router.post("/{deck_id}/backfill-pos", response_model=BackfillPosResponse)
async def backfill_pos(
    deck_id: UUID,
    body: BackfillPosRequest | None = None,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Обновить карточки без part_of_speech: добавить переводы по частям речи (сущ., глагол, прил., нареч.)."""
    deck = await deck_repo.get_deck_by_id(db, deck_id, current_user.id)
    if not deck:
        raise HTTPException(status_code=404, detail="Deck not found")
    limit = (body or BackfillPosRequest()).limit
    cards = await card_repo.get_cards_missing_pos(db, current_user.id, deck_id=deck_id, limit=limit)
    updated = 0
    created = 0
    skipped = 0
    errors = 0
    batch_size = gemini_service.BATCH_ENRICH_SIZE
    for offset in range(0, len(cards), batch_size):
        chunk = cards[offset : offset + batch_size]
        words = [card.word or "" for card in chunk]
        try:
            batch_results = gemini_service.enrich_words_with_pos_batch(words)
        except Exception:
            errors += len(chunk)
            continue
        for card, data in zip(chunk, batch_results):
            try:
                senses = data.get("senses") or []
                if not senses:
                    skipped += 1
                    continue
                transcription = data.get("transcription")
                pronunciation_url = gemini_service.get_pronunciation_url(card.word or "")
                first = senses[0]
                await card_repo.update_card(
                    db, card,
                    part_of_speech=first.get("part_of_speech"),
                    translation=first.get("translation", card.translation),
                    example=first.get("example") or card.example,
                    transcription=transcription or card.transcription,
                    pronunciation_url=pronunciation_url or card.pronunciation_url,
                )
                updated += 1
                for sense in senses[1:]:
                    pos = sense.get("part_of_speech")
                    if not pos:
                        continue
                    if await card_repo.exists_card_in_deck_with_pos(db, deck_id, card.word or "", pos):
                        continue
                    await card_repo.create_card(
                        db, deck_id, card.word or "", sense.get("translation", ""),
                        example=sense.get("example"),
                        transcription=transcription,
                        pronunciation_url=pronunciation_url,
                        part_of_speech=pos,
                    )
                    created += 1
            except Exception:
                errors += 1
    await db.commit()
    return BackfillPosResponse(updated=updated, created=created, skipped=skipped, errors=errors)


@router.post("/{deck_id}/remove-duplicates")
async def remove_duplicates(
    deck_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Удалить дубликаты слов в колоде (оставить одну карточку на слово)."""
    deck = await deck_repo.get_deck_by_id(db, deck_id, current_user.id)
    if not deck:
        raise HTTPException(status_code=404, detail="Deck not found")
    removed = await card_repo.remove_duplicate_cards_in_deck(db, deck_id)
    await db.commit()
    return {"removed": removed}


@router.post("/{deck_id}/synonym-groups")
async def apply_synonym_groups(
    deck_id: UUID,
    body: ApplySynonymGroupsRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Set synonym_group_id for cards: each inner list of card_ids gets one group id. Clears previous groups in deck."""
    deck = await deck_repo.get_deck_by_id(db, deck_id, current_user.id)
    if not deck:
        raise HTTPException(status_code=404, detail="Deck not found")
    all_cards = await card_repo.get_cards_by_deck(db, deck_id)
    for card in all_cards:
        await card_repo.update_card(db, card, synonym_group_id=None)
    for card_ids in body.groups:
        if len(card_ids) < 2:
            continue
        group_id = uuid4()
        for cid in card_ids:
            card = await card_repo.get_card_by_id(db, UUID(cid), current_user.id)
            if card and card.deck_id == deck_id:
                await card_repo.update_card(db, card, synonym_group_id=group_id)
    await db.commit()
    return {"applied": len(body.groups)}
