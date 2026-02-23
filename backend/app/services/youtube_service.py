import os
import tempfile
import yt_dlp
import logging
import random

logger = logging.getLogger(__name__)

async def download_youtube_audio(url: str) -> str:
    """
    Downloads audio from a YouTube video and returns the path to the temporary file.
    """
    logger.info(f"Downloading audio from YouTube URL: {url}")
    
    # Create a temporary file path
    temp_dir = tempfile.gettempdir()
    output_template = os.path.join(temp_dir, "%(id)s.%(ext)s")

    ydl_opts = {
        'format': 'bestaudio/best',
        'postprocessors': [{
            'key': 'FFmpegExtractAudio',
            'preferredcodec': 'mp3',
            'preferredquality': '192',
        }],
        'outtmpl': output_template,
        'quiet': True,
        'no_warnings': True,
    }

    try:
        # We run this synchronously since yt_dlp does not have proper async API
        # To avoid blocking the event loop entirely, this could be run in an executor
        # but for simplicity, we will just use it directly.
        import asyncio
        loop = asyncio.get_event_loop()
        
        def _download():
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info_dict = ydl.extract_info(url, download=True)
                video_id = info_dict.get('id', None)
                expected_filename = os.path.join(temp_dir, f"{video_id}.mp3")
                return expected_filename

        filename = await loop.run_in_executor(None, _download)
        
        logger.info(f"Successfully downloaded audio to: {filename}")
        return filename
    except Exception as e:
        logger.error(f"Error downloading YouTube audio: {e}")
        raise ValueError(f"Could not download audio from the provided URL: {str(e)}")

async def search_ielts_video() -> dict:
    """
    Searches for IELTS listening practice videos and returns a random selection.
    """
    logger.info("Searching for a random IELTS listening video")
    
    queries = [
        "ielts listening practice test short",
        "ielts listening part 1 practice",
        "ielts listening part 2 practice",
        "ielts listening part 3 practice",
        "ielts listening part 4 practice"
    ]
    query_str = f"ytsearch10:{random.choice(queries)}"
    
    ydl_opts = {
        'extract_flat': True,
        'quiet': True,
    }

    try:
        import asyncio
        loop = asyncio.get_event_loop()
        
        def _search():
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(query_str, download=False)
                if 'entries' in info and len(info['entries']) > 0:
                    entries = list(info['entries'])
                    video = random.choice(entries)
                    return {
                        "video_id": video.get("id"),
                        "url": video.get("url") or f"https://www.youtube.com/watch?v={video.get('id')}",
                        "title": video.get("title")
                    }
                return None

        result = await loop.run_in_executor(None, _search)
        if not result:
            raise ValueError("No search results found.")
        
        logger.info(f"Selected random video: {result['url']}")
        return result
    except Exception as e:
        logger.error(f"Error searching for IELTS video: {e}")
        raise ValueError(f"Could not search for a video: {str(e)}")
