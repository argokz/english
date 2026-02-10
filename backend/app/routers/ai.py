from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.dependencies import get_current_user
from app.models.user import User
from app.db.session import get_db
from app.db.repositories import deck_repo, card_repo
from app.services import gemini_service
from app.schemas.ai import (
    GenerateWordsRequest,
    EnrichWordRequest,
    EnrichWordResponse,
    SimilarWordItem,
    BackfillTranscriptionsRequest,
    BackfillTranscriptionsResponse,
)

router = APIRouter()


@router.post("/generate-words")
async def generate_words(
    body: GenerateWordsRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    deck_id = UUID(body.deck_id)
    deck = await deck_repo.get_deck_by_id(db, deck_id, current_user.id)
    if not deck:
        raise HTTPException(status_code=404, detail="Deck not found")
    try:
        items = gemini_service.generate_word_list(level=body.level, topic=body.topic, count=body.count)
    except ValueError as e:
        # Ошибка превышения квоты
        raise HTTPException(status_code=429, detail=str(e))
    created = 0
    for item in items:
        emb = gemini_service.get_embedding(f"{item['word']}: {item['translation']}")
        pronunciation_url = gemini_service.get_pronunciation_url(item["word"])
        await card_repo.create_card(
            db,
            deck_id,
            item["word"],
            item["translation"],
            item.get("example"),
            embedding=emb,
            transcription=item.get("transcription"),
            pronunciation_url=pronunciation_url,
        )
        created += 1
    await db.commit()
    return {"created": created}


@router.post("/enrich-word", response_model=EnrichWordResponse)
async def enrich_word(
    body: EnrichWordRequest,
    current_user: User = Depends(get_current_user),
):
    if not body.word.strip():
        raise HTTPException(status_code=400, detail="word is required")
    word = body.word.strip()
    try:
        result = gemini_service.enrich_word(word)
    except ValueError as e:
        # Ошибка превышения квоты
        raise HTTPException(status_code=429, detail=str(e))
    pronunciation_url = gemini_service.get_pronunciation_url(word)
    return EnrichWordResponse(
        translation=result.get("translation", ""),
        example=result.get("example", ""),
        transcription=result.get("transcription", ""),
        pronunciation_url=pronunciation_url,
    )


@router.post("/backfill-transcriptions", response_model=BackfillTranscriptionsResponse)
async def backfill_transcriptions(
    body: BackfillTranscriptionsRequest | None = None,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Update cards that have no transcription or pronunciation_url using Gemini + Google TTS."""
    body = body or BackfillTranscriptionsRequest()
    deck_id = UUID(body.deck_id) if body.deck_id else None
    if body.deck_id and deck_id:
        deck = await deck_repo.get_deck_by_id(db, deck_id, current_user.id)
        if not deck:
            raise HTTPException(status_code=404, detail="Deck not found")
    cards = await card_repo.get_cards_missing_transcription(
        db, current_user.id, deck_id=deck_id, limit=body.limit
    )
    updated = 0
    for card in cards:
        try:
            result = gemini_service.enrich_word(card.word)
            transcription = result.get("transcription") or ""
            pronunciation_url = gemini_service.get_pronunciation_url(card.word)
            await card_repo.update_card(
                db, card, transcription=transcription, pronunciation_url=pronunciation_url
            )
            updated += 1
        except ValueError:
            # Превышение квоты - прекращаем обработку
            break
        except Exception:
            continue
    await db.commit()
    return BackfillTranscriptionsResponse(updated=updated)


@router.get("/similar-words", response_model=list[SimilarWordItem])
async def similar_words(
    word: str,
    deck_id: str | None = None,
    limit: int = 10,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Return similar words by embedding. If deck_id given, exclude cards already in that deck."""
    if not word.strip():
        return []
    embedding = gemini_service.get_embedding(word.strip())
    if not embedding:
        return []
    # pgvector: ORDER BY embedding <=> query_vector LIMIT n
    # We need to pass the embedding as a string like '[0.1,0.2,...]' for the query
    vec_str = "[" + ",".join(str(x) for x in embedding) + "]"
    if deck_id:
        sql = text("""
            SELECT c.id, c.word, c.translation, c.example
            FROM cards c
            JOIN decks d ON d.id = c.deck_id
            WHERE c.embedding IS NOT NULL AND d.user_id = :user_id AND c.deck_id != :deck_id
            ORDER BY c.embedding <=> CAST(:vec AS vector)
            LIMIT :lim
        """)
        params = {"vec": vec_str, "lim": limit, "user_id": str(current_user.id), "deck_id": deck_id}
    else:
        sql = text("""
            SELECT c.id, c.word, c.translation, c.example
            FROM cards c
            JOIN decks d ON d.id = c.deck_id
            WHERE c.embedding IS NOT NULL AND d.user_id = :user_id
            ORDER BY c.embedding <=> CAST(:vec AS vector)
            LIMIT :lim
        """)
        params = {"vec": vec_str, "lim": limit, "user_id": str(current_user.id)}
    try:
        result = await db.execute(sql, params)
        rows = result.fetchall()
    except Exception:
        return []
    return [
        SimilarWordItem(
            word=r.word,
            translation=r.translation,
            example=r.example,
            card_id=str(r.id),
        )
        for r in rows
    ]
