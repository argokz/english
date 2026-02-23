from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks
from pydantic import BaseModel
import os
import logging
import re
from uuid import UUID
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.exc import IntegrityError

from app.dependencies import get_current_user, get_db
from app.models.user import User
from app.services import youtube_service, transcription_service, gemini_service
from app.db.repositories import youtube_repo

logger = logging.getLogger(__name__)

router = APIRouter()

class YouTubeProcessRequest(BaseModel):
    url: str | None = None
    target_lang: str = "ru"

class YouTubeProcessResponse(BaseModel):
    id: UUID
    video_id: str
    url: str
    transcription: str
    translation: str
    summary: str

class VideoHistoryResponse(BaseModel):
    id: UUID
    video_id: str
    url: str
    title: str | None = None
    created_at: str

class AskQuestionRequest(BaseModel):
    question: str

def cleanup_file(filepath: str):
    try:
        if os.path.exists(filepath):
            os.remove(filepath)
            logger.info(f"Cleaned up temporary file: {filepath}")
    except Exception as e:
        logger.error(f"Failed to clean up file {filepath}: {e}")

@router.post("/process", response_model=YouTubeProcessResponse)
async def process_youtube_video(
    body: YouTubeProcessRequest,
    background_tasks: BackgroundTasks,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    try:
        # Step 1: Handle Autosearch or Exact URL
        url_to_process = body.url
        video_id = None
        if not url_to_process:
            logger.info("No URL provided, searching for an IELTS listening video...")
            video_info = await youtube_service.search_ielts_video()
            url_to_process = video_info["url"]
            video_id = video_info["video_id"]
        else:
            match = re.search(r"(?:v=|\/)([0-9A-Za-z_-]{11}).*", url_to_process)
            video_id = match.group(1) if match else "unknown"

        # Step 2: Check DB Cache
        if video_id and video_id != "unknown":
            existing_video = await youtube_repo.get_video_by_youtube_id(db, video_id)
            if existing_video:
                logger.info(f"Video {video_id} found in DB cache. Returning immediately.")
                await youtube_repo.add_to_user_history(db, current_user.id, existing_video.id)
                await db.commit()
                return YouTubeProcessResponse(
                    id=existing_video.id,
                    video_id=existing_video.video_id,
                    url=existing_video.url,
                    transcription=existing_video.transcription,
                    translation=existing_video.translation,
                    summary=existing_video.summary
                )

        # Step 3: Download Audio
        logger.info(f"User {current_user.id} requested to process YouTube video: {url_to_process}")
        audio_path = await youtube_service.download_youtube_audio(url_to_process)
        
        # Add to background tasks to ensure cleanup even if the next steps fail
        background_tasks.add_task(cleanup_file, audio_path)

        # Step 4: Transcribe Audio
        transcription_result = await transcription_service.transcribe_audio_file(audio_path, language="en")
        
        segments = transcription_result.get("segments", [])
        if not segments:
            raise HTTPException(status_code=500, detail="Transcription succeeded but no segments were found.")
            
        full_transcript = " ".join([segment.get("text", "") for segment in segments])

        # Step 5: Translate and Summarize
        summary_result = gemini_service.summarize_youtube_video(full_transcript, target_lang=body.target_lang)
        translation_text = summary_result.get("translation", "")
        summary_text = summary_result.get("summary", "")

        # Step 6: Save to DB and User History
        try:
            new_video = await youtube_repo.create_video(db, video_id, url_to_process, full_transcript, translation_text, summary_text)
        except IntegrityError:
            # Race condition: someone else saved it while we were transcribing
            await db.rollback()
            new_video = await youtube_repo.get_video_by_youtube_id(db, video_id)
            if not new_video:
                raise HTTPException(status_code=500, detail="Conflict during video creation and could not retrieve existing video.")
        
        await youtube_repo.add_to_user_history(db, current_user.id, new_video.id)
        await db.commit()

        return YouTubeProcessResponse(
            id=new_video.id,
            video_id=new_video.video_id,
            url=new_video.url,
            transcription=new_video.transcription,
            translation=translation_text,
            summary=summary_text
        )
        
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.exception("Unexpected error processing YouTube video")
        raise HTTPException(status_code=500, detail="An internal error occurred during processing.")

@router.get("/history")
async def get_youtube_history(
    limit: int = 50,
    offset: int = 0,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    try:
        history = await youtube_repo.get_user_history(db, current_user.id, limit, offset)
        results = []
        for h in history:
            vid = h.video
            results.append({
                "id": vid.id,
                "video_id": vid.video_id,
                "url": vid.url,
                "transcription": vid.transcription,
                "viewed_at": h.viewed_at
            })
        return results
    except Exception as e:
        logger.error(f"Error fetching youtube history: {e}")
        raise HTTPException(status_code=500, detail="Failed to fetch history.")

@router.post("/{video_id}/questions")
async def generate_questions(
    video_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    video = await youtube_repo.get_video_by_id(db, video_id)
    if not video:
        raise HTTPException(status_code=404, detail="Video not found in DB.")
        
    try:
        questions_data = gemini_service.generate_ielts_listening_questions(video.transcription)
        return questions_data
    except Exception as e:
        logger.error(f"Error generating questions: {e}")
        raise HTTPException(status_code=500, detail="Failed to generate questions.")

@router.post("/{video_id}/ask")
async def ask_question_about_video(
    video_id: UUID,
    body: AskQuestionRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    video = await youtube_repo.get_video_by_id(db, video_id)
    if not video:
        raise HTTPException(status_code=404, detail="Video not found in DB.")
        
    try:
        # Re-use our freeform AI method or write a specific prompt
        prompt = f"Ответь на вопрос по тексту этого видео. Транскрипция:\n{video.transcription}\n\nВопрос: {body.question}"
        # using translation logic loosely or general gemini text 
        answer = gemini_service._generate_content_with_fallback(prompt)
        return {"answer": answer}
    except Exception as e:
        logger.error(f"Error answering question: {e}")
        raise HTTPException(status_code=500, detail="Failed to answer the question.")
