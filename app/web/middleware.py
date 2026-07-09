from fastapi import Request, HTTPException, status
from fastapi.responses import Response, JSONResponse
import base64
from app.infra.repository import FeedTokenRepository
from app.web.auth_utils import verify_feed_password, verify_password

async def startup_check_middleware(request: Request, call_next):
    """
    Middleware to block UI access during startup (model loading).
    Allows health endpoint and static files to be accessed.
    """
    path = request.url.path
    
    # Allow health endpoint, static files, and API docs during startup
    if path in ['/health', '/', '/api/docs', '/api/redoc'] or path.startswith('/static/') or path.startswith('/api/'):
        return await call_next(request)
    
    # Check startup status
    from app.infra.database import get_db_connection
    try:
        with get_db_connection() as conn:
            row = conn.execute("SELECT startup_complete FROM app_settings WHERE id = 1").fetchone()
            startup_complete = row['startup_complete'] if row else False
            if not startup_complete:
                return JSONResponse(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    content={"detail": "Application is starting up. Please wait a moment."}
                )
    except Exception:
        # If we can't check the status, allow the request (fail open)
        pass
    
    return await call_next(request)

async def feed_auth_middleware(request: Request, call_next):
    """
    Middleware to protect /feeds/* and /audio/* routes with HTTP Basic Auth.
    - If user auth is enabled: uses user credentials
    - If user auth is disabled: uses global feed credentials
    """
    path = request.url.path
    
    # Only protect feeds and audio routes
    if not (path.startswith('/feeds/') or path.startswith('/audio/')):
        return await call_next(request)
    
    # Check if feed auth is enabled
    from app.web.router import get_global_settings
    settings = get_global_settings()
    
    # Determine if we should enforce auth
    if not settings.get('enable_feed_auth'):
        return await call_next(request)

    # Preferred protected-feed mode: generated bearer tokens.
    token = request.query_params.get('token')
    if token and FeedTokenRepository().validate(token):
        return await call_next(request)
    
    # Check for Authorization header
    auth_header = request.headers.get('Authorization')
    encoded_credentials = None
    
    if auth_header and auth_header.startswith('Basic '):
        encoded_credentials = auth_header.split(' ')[1]
    else:
        # Fallback: Check for ?auth= query parameter
        encoded_credentials = request.query_params.get('auth')
    
    if not encoded_credentials:
        return Response(
            status_code=status.HTTP_401_UNAUTHORIZED,
            headers={'WWW-Authenticate': 'Basic realm="Podcast Feeds"'}
        )
    
    # Decode credentials
    try:
        decoded_credentials = base64.b64decode(encoded_credentials).decode('utf-8')
        username, password = decoded_credentials.split(':', 1)
    except Exception:
        return Response(
            status_code=status.HTTP_401_UNAUTHORIZED,
            headers={'WWW-Authenticate': 'Basic realm="Podcast Feeds"'}
        )
    
    # Determine which credentials to check
    if settings.get('auth_enabled'):
        # User auth is enabled - check against users table
        from app.infra.database import get_db_connection
        with get_db_connection() as conn:
            user_row = conn.execute("SELECT password_hash FROM users WHERE username = ?", (username,)).fetchone()
        
        if not user_row or not verify_password(password, user_row['password_hash']):
            return Response(
                status_code=status.HTTP_401_UNAUTHORIZED,
                headers={'WWW-Authenticate': 'Basic realm="Podcast Feeds"'}
            )
    else:
        # User auth is disabled - check against global feed credentials
        expected_username = settings.get('feed_auth_username')
        expected_password_hash = settings.get('feed_auth_password')
        
        if not expected_username or not expected_password_hash:
            return Response(
                status_code=status.HTTP_401_UNAUTHORIZED,
                headers={'WWW-Authenticate': 'Basic realm="Podcast Feeds"'}
            )
        
        if username != expected_username:
            return Response(
                status_code=status.HTTP_401_UNAUTHORIZED,
                headers={'WWW-Authenticate': 'Basic realm="Podcast Feeds"'}
            )
        
        if not verify_feed_password(password, expected_password_hash):
            return Response(
                status_code=status.HTTP_401_UNAUTHORIZED,
                headers={'WWW-Authenticate': 'Basic realm="Podcast Feeds"'}
            )
    
    # Authentication successful
    return await call_next(request)
