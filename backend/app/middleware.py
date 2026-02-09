import time
import logging
from typing import Callable
from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware

logger = logging.getLogger(__name__)


class LoggingMiddleware(BaseHTTPMiddleware):
    """Middleware для логирования всех HTTP запросов и ответов"""
    
    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        # Логируем входящий запрос
        start_time = time.time()
        
        # Получаем информацию о запросе
        method = request.method
        url = str(request.url)
        client_host = request.client.host if request.client else "unknown"
        user_agent = request.headers.get("user-agent", "unknown")
        
        # Получаем query параметры
        query_params = dict(request.query_params)
        
        # Логируем входящий запрос
        log_msg = f"→ {method} {url}"
        if query_params:
            log_msg += f" | Query: {query_params}"
        log_msg += f" | Client: {client_host}"
        
        logger.info(log_msg)
        
        # Обрабатываем запрос
        try:
            response = await call_next(request)
            
            # Вычисляем время обработки
            process_time = time.time() - start_time
            
            # Получаем статус код
            status_code = response.status_code
            
            # Логируем ответ
            log_level = logging.INFO
            if status_code >= 500:
                log_level = logging.ERROR
            elif status_code >= 400:
                log_level = logging.WARNING
            
            # Для 404 логируем более детально
            if status_code == 404:
                logger.warning(
                    f"← {method} {url} | Status: 404 NOT FOUND | Time: {process_time:.3f}s | "
                    f"Path: {request.url.path} | Available routes might not match"
                )
            else:
                logger.log(
                    log_level,
                    f"← {method} {url} | Status: {status_code} | Time: {process_time:.3f}s"
                )
            
            # Добавляем заголовок с временем обработки
            response.headers["X-Process-Time"] = str(process_time)
            
            return response
            
        except Exception as e:
            # Логируем исключения
            process_time = time.time() - start_time
            logger.error(
                f"✗ {method} {url} | Error: {str(e)} | Time: {process_time:.3f}s",
                exc_info=True
            )
            raise

