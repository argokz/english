from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.dependencies import get_current_user
from app.models.user import User
from app.db.session import get_db
from app.db.repositories import deck_repo, card_repo, writing_repo
from app.services import gemini_service
from app.schemas.ai import (
    GenerateWordsRequest,
    TranslateRequest,
    TranslateResponse,
    EnrichWordRequest,
    EnrichWordResponse,
    EnrichWordSense,
    SimilarWordItem,
    BackfillTranscriptionsRequest,
    BackfillTranscriptionsResponse,
    SynonymsResponse,
    SuggestSynonymGroupsResponse,
    SynonymGroupItem,
    ApplySynonymGroupsRequest,
    EvaluateWritingRequest,
    EvaluateWritingResponse,
    WritingErrorItem,
    WritingSubmissionListItem,
    WritingSubmissionResponse,
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
    skipped_duplicates = 0
    for item in items:
        if await card_repo.exists_card_in_deck(db, deck_id, item["word"]):
            skipped_duplicates += 1
            continue
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
    return {"created": created, "skipped_duplicates": skipped_duplicates}


@router.post("/translate", response_model=TranslateResponse)
async def translate(
    body: TranslateRequest,
    current_user: User = Depends(get_current_user),
):
    if not body.text.strip():
        raise HTTPException(status_code=400, detail="text is required")
    sl = body.source_lang.strip().lower()
    tl = body.target_lang.strip().lower()
    if sl not in ("ru", "en") or tl not in ("ru", "en") or sl == tl:
        raise HTTPException(status_code=400, detail="source_lang and target_lang must be 'ru' and 'en' (different)")
    try:
        translation = gemini_service.translate(body.text.strip(), sl, tl)
    except ValueError as e:
        raise HTTPException(status_code=429, detail=str(e))
    return TranslateResponse(translation=translation, source_lang=sl, target_lang=tl)


@router.post("/enrich-word", response_model=EnrichWordResponse)
async def enrich_word(
    body: EnrichWordRequest,
    current_user: User = Depends(get_current_user),
):
    if not body.word.strip():
        raise HTTPException(status_code=400, detail="word is required")
    word = body.word.strip()
    try:
        result = gemini_service.enrich_word_with_pos(word)
    except ValueError as e:
        raise HTTPException(status_code=429, detail=str(e))
    pronunciation_url = gemini_service.get_pronunciation_url(word)
    senses = result.get("senses") or []
    first_translation = senses[0]["translation"] if senses else ""
    first_example = senses[0]["example"] if senses else ""
    return EnrichWordResponse(
        translation=first_translation,
        example=first_example,
        transcription=result.get("transcription") or None,
        pronunciation_url=pronunciation_url,
        senses=[EnrichWordSense(part_of_speech=s["part_of_speech"], translation=s["translation"], example=s["example"]) for s in senses],
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


def _word_count(text: str) -> int:
    return len([w for w in (text or "").split() if w.strip()])


@router.post("/evaluate-writing", response_model=EvaluateWritingResponse)
async def evaluate_writing(
    body: EvaluateWritingRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Проверка текста для IELTS Writing: оценка, исправления, ошибки, рекомендации. Сохраняется в историю."""
    word_count = _word_count(body.text)
    try:
        result = gemini_service.evaluate_ielts_writing(
            body.text,
            word_limit_min=body.word_limit_min,
            word_limit_max=body.word_limit_max,
            task_type=body.task_type,
        )
    except ValueError as e:
        raise HTTPException(status_code=429, detail=str(e))
    errors = [
        WritingErrorItem(
            type=e.get("type", ""),
            original=e.get("original", ""),
            correction=e.get("correction", ""),
            explanation=e.get("explanation", ""),
        )
        for e in result.get("errors") or []
        if isinstance(e, dict)
    ]
    errors_data = [e.model_dump() for e in errors]
    # Преобразуем recommendations из списка в строку, если это список
    recommendations = result.get("recommendations", "")
    if isinstance(recommendations, list):
        recommendations = "\n".join(str(r) for r in recommendations)
    elif recommendations is None:
        recommendations = ""
    sub = await writing_repo.create_writing_submission(
        db,
        current_user.id,
        original_text=body.text,
        word_count=word_count,
        evaluation=result.get("evaluation", ""),
        corrected_text=result.get("corrected_text", ""),
        recommendations=recommendations,
        time_used_seconds=body.time_used_seconds,
        time_limit_minutes=body.time_limit_minutes,
        word_limit_min=body.word_limit_min,
        word_limit_max=body.word_limit_max,
        task_type=body.task_type,
        errors=errors_data,
    )
    await db.commit()
    return EvaluateWritingResponse(
        submission_id=str(sub.id),
        word_count=word_count,
        time_used_seconds=body.time_used_seconds,
        evaluation=result.get("evaluation", ""),
        corrected_text=result.get("corrected_text", ""),
        errors=errors,
        recommendations=result.get("recommendations", ""),
    )


@router.get("/writing-history", response_model=list[WritingSubmissionListItem])
async def get_writing_history(
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Список сохранённых проверок текста (история)."""
    subs = await writing_repo.get_writing_submissions_by_user(db, current_user.id, limit=limit, offset=offset)
    return [
        WritingSubmissionListItem(
            id=str(s.id),
            word_count=s.word_count,
            time_used_seconds=s.time_used_seconds,
            created_at=s.created_at,
            evaluation_preview=(s.evaluation or "")[:100] + ("…" if len(s.evaluation or "") > 100 else ""),
        )
        for s in subs
    ]


@router.get("/writing-history/{submission_id}", response_model=WritingSubmissionResponse)
async def get_writing_submission(
    submission_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Одна запись из истории: полный текст, оценка, исправления, ошибки, рекомендации."""
    sub = await writing_repo.get_writing_submission_by_id(db, submission_id, current_user.id)
    if not sub:
        raise HTTPException(status_code=404, detail="Not found")
    errors = [
        WritingErrorItem(
            type=e.get("type", ""),
            original=e.get("original", ""),
            correction=e.get("correction", ""),
            explanation=e.get("explanation", ""),
        )
        for e in (sub.errors or [])
        if isinstance(e, dict)
    ]
    return WritingSubmissionResponse(
        id=str(sub.id),
        original_text=sub.original_text,
        word_count=sub.word_count,
        time_used_seconds=sub.time_used_seconds,
        time_limit_minutes=sub.time_limit_minutes,
        word_limit_min=sub.word_limit_min,
        word_limit_max=sub.word_limit_max,
        task_type=sub.task_type,
        evaluation=sub.evaluation,
        corrected_text=sub.corrected_text,
        errors=errors,
        recommendations=sub.recommendations,
        created_at=sub.created_at,
    )


@router.get("/synonyms", response_model=SynonymsResponse)
async def get_synonyms(
    word: str,
    deck_id: str,
    limit: int = 10,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get synonyms for word via Gemini; return which of those are already in the deck as cards."""
    if not word.strip():
        return SynonymsResponse(synonyms=[], cards_in_deck=[])
    deck = await deck_repo.get_deck_by_id(db, UUID(deck_id), current_user.id)
    if not deck:
        raise HTTPException(status_code=404, detail="Deck not found")
    synonyms = gemini_service.get_synonyms(word.strip(), limit=limit)
    synonym_set = {s.lower() for s in synonyms}
    cards = await card_repo.get_cards_by_deck(db, UUID(deck_id))
    cards_in_deck = [
        SimilarWordItem(word=c.word, translation=c.translation, example=c.example, card_id=str(c.id))
        for c in cards
        if c.word and c.word.strip().lower() in synonym_set
    ]
    return SynonymsResponse(synonyms=synonyms, cards_in_deck=cards_in_deck)


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


def _build_synonym_groups(cards: list, synonym_map: dict[str, set[str]]) -> list[tuple[list[str], list[str]]]:
    """Build groups: list of (card_ids, words). synonym_map: card_id -> set of synonym words (lower)."""
    word_to_card_id = {}
    for c in cards:
        w = (c.word or "").strip().lower()
        if w:
            word_to_card_id[w] = str(c.id)
    # Graph: card_id -> set of card_ids that are synonyms (same group)
    graph: dict[str, set[str]] = {}
    for c in cards:
        cid = str(c.id)
        graph.setdefault(cid, set())
        syns = synonym_map.get(cid, set())
        for w in syns:
            if w in word_to_card_id and word_to_card_id[w] != cid:
                graph[cid].add(word_to_card_id[w])
    # Connected components
    visited = set()

    def dfs(nid: str, comp: set[str]) -> None:
        visited.add(nid)
        comp.add(nid)
        for nb in graph.get(nid, set()):
            if nb not in visited:
                dfs(nb, comp)

    groups = []
    for c in cards:
        cid = str(c.id)
        if cid in visited:
            continue
        comp = set()
        dfs(cid, comp)
        if len(comp) >= 2:
            card_ids = list(comp)
            words = [c.word for c in cards if str(c.id) in comp]
            groups.append((card_ids, words))
    return groups


@router.post("/synonym-groups/suggest", response_model=SuggestSynonymGroupsResponse)
async def suggest_synonym_groups(
    deck_id: str,
    limit: int = 30,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Suggest synonym groups for deck: for each card get Gemini synonyms, cluster, return groups (2+ cards)."""
    deck = await deck_repo.get_deck_by_id(db, UUID(deck_id), current_user.id)
    if not deck:
        raise HTTPException(status_code=404, detail="Deck not found")
    cards = await card_repo.get_cards_by_deck(db, UUID(deck_id))
    cards = cards[:limit]
    synonym_map: dict[str, set[str]] = {}
    for c in cards:
        try:
            syns = gemini_service.get_synonyms(c.word or "", limit=12)
            synonym_map[str(c.id)] = {s.lower() for s in syns}
        except Exception:
            synonym_map[str(c.id)] = set()
    raw_groups = _build_synonym_groups(cards, synonym_map)
    return SuggestSynonymGroupsResponse(
        groups=[
            SynonymGroupItem(words=words, card_ids=card_ids)
            for card_ids, words in raw_groups
        ]
    )
