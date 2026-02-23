import logging
import httpx
from app.config import settings

logger = logging.getLogger(__name__)

async def transcribe_audio_file(file_path: str, language: str = None) -> dict:
    """
    Sends an audio file to the remote Whisper worker for transcription.
    Returns the transcription result.
    """
    logger.info(f"Sending audio file {file_path} for transcription to {settings.whisper_worker_url}")
    
    url = f"{settings.whisper_worker_url.rstrip('/')}/transcribe"
    
    params = {}
    if language:
        params["language"] = language

    try:
        # httpx supports async file uploads
        timeout = httpx.Timeout(600.0) # Transcription can take a few minutes
        async with httpx.AsyncClient(timeout=timeout) as client:
            with open(file_path, "rb") as f:
                files = {"file": (file_path, f, "audio/mpeg")}
                response = await client.post(url, files=files, params=params)
                
            response.raise_for_status()
            data = response.json()
            
            if data.get("status") == "error":
                logger.error(f"Worker returned an error: {data.get('error')}")
                raise ValueError(f"Transcription failed on worker: {data.get('error')}")
                
            logger.info("Successfully transcribed audio file")
            return data
    except httpx.HTTPError as e:
        logger.error(f"HTTP error during transcription request: {e}")
        raise ValueError(f"Failed to communicate with transcription worker: {str(e)}")
    except Exception as e:
        logger.error(f"Error during transcription: {e}")
        raise ValueError(f"Transcription process failed: {str(e)}")
