from fastapi import FastAPI, BackgroundTasks, Request, HTTPException, Header
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse, HTMLResponse
import config
import db_client
import assembly_service
import ai_service
import auth_service
import logging
import uuid
import time
import os
from datetime import datetime, timedelta
from typing import Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="EchoMind Backend")

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=config.CORS_ALLOW_ORIGINS,
    allow_credentials=config.CORS_ALLOW_CREDENTIALS,
    allow_methods=config.CORS_ALLOW_METHODS,
    allow_headers=config.CORS_ALLOW_HEADERS,
)


@app.middleware("http")
async def log_requests(request: Request, call_next):
    request_id = str(uuid.uuid4())[:8]
    start = time.time()
    logger.info(f"[REQ {request_id}] -> {request.method} {request.url.path}")
    try:
        response = await call_next(request)
        duration_ms = int((time.time() - start) * 1000)
        logger.info(
            f"[REQ {request_id}] <- {request.method} {request.url.path} status={response.status_code} durationMs={duration_ms}"
        )
        return response
    except Exception as e:
        duration_ms = int((time.time() - start) * 1000)
        logger.exception(
            f"[REQ {request_id}] !! {request.method} {request.url.path} failed after {duration_ms}ms: {e}"
        )
        raise


def resolve_user_id(request: Request, x_user_id: Optional[str] = None) -> str:
    user_id = (
        x_user_id or request.headers.get("x-user-id") or request.headers.get("user-id")
    )
    if not user_id:
        raise HTTPException(status_code=400, detail="x-user-id header is required")
    return user_id


@app.on_event("startup")
def startup_event():
    config.validate_config()
    logger.info("Configuration validated.")
    logger.info(f"Google Client ID configured: {bool(config.GOOGLE_CLIENT_ID)}")


@app.get("/health")
def health_check():
    return {"status": "ok", "message": "EchoMind backend is running"}


# ============ Authentication Endpoints ============


@app.post("/auth/register")
async def register_with_email(request: Request):
    """Register a new user with email and password."""
    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON body")

    email = body.get("email", "").strip().lower()
    password = body.get("password", "")
    name = body.get("name", "").strip()

    # Validate email
    if not email or not auth_service.validate_email(email):
        raise HTTPException(
            status_code=400, detail="Please enter a valid email address"
        )

    # Validate password
    is_valid, error_msg = auth_service.validate_password(password)
    if not is_valid:
        raise HTTPException(status_code=400, detail=error_msg)

    # Validate name
    is_valid, error_msg = auth_service.validate_name(name)
    if not is_valid:
        raise HTTPException(status_code=400, detail=error_msg)

    # Check if user already exists
    existing_user = await db_client.get_user_by_email(email)
    if existing_user:
        raise HTTPException(
            status_code=409, detail="An account with this email already exists"
        )

    # Create password hash
    password_hash = auth_service.create_password_hash(password)

    # Create user
    user = await db_client.create_user_with_password(
        email=email,
        name=name,
        password_hash=password_hash,
    )

    # Create JWT token
    access_token = auth_service.create_jwt_token(user["id"], user["email"])

    logger.info(f"[AUTH] Registration success user={user['id']} email={user['email']}")

    return {
        "success": True,
        "access_token": access_token,
        "user": {
            "id": user["id"],
            "email": user["email"],
            "name": user.get("name"),
            "calendar_connected": user.get("calendar_connected", False),
        },
    }


@app.post("/auth/login")
async def login_with_email(request: Request):
    """Login with email and password."""
    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON body")

    email = body.get("email", "").strip().lower()
    password = body.get("password", "")

    if not email or not password:
        raise HTTPException(status_code=400, detail="Email and password are required")

    # Get user by email
    user = await db_client.get_user_by_email(email)
    if not user:
        raise HTTPException(status_code=401, detail="Invalid email or password")

    # Check if user has a password (might be Google-only account)
    if not user.get("password_hash"):
        raise HTTPException(
            status_code=401,
            detail="This account uses Google Sign-In. Please sign in with Google.",
        )

    # Verify password
    if not auth_service.verify_password(password, user["password_hash"]):
        raise HTTPException(status_code=401, detail="Invalid email or password")

    # Create JWT token
    access_token = auth_service.create_jwt_token(user["id"], user["email"])

    logger.info(f"[AUTH] Login success user={user['id']} email={user['email']}")

    return {
        "success": True,
        "access_token": access_token,
        "user": {
            "id": user["id"],
            "email": user["email"],
            "name": user.get("name"),
            "calendar_connected": user.get("calendar_connected", False),
        },
    }


@app.post("/auth/google")
async def google_auth(request: Request):
    """Authenticate with Google ID token from mobile app."""
    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON body")

    id_token = body.get("id_token")
    if not id_token:
        raise HTTPException(status_code=400, detail="id_token is required")

    # Verify the Google ID token
    google_user = await auth_service.verify_google_id_token(id_token)
    if not google_user:
        raise HTTPException(status_code=401, detail="Invalid Google ID token")

    # Get or create user in database
    user = await db_client.get_or_create_user(
        email=google_user["email"],
        name=google_user.get("name"),
        google_id=google_user.get("google_id"),
        picture_url=google_user.get("picture"),
    )

    # Create JWT token
    access_token = auth_service.create_jwt_token(user["id"], user["email"])

    logger.info(f"[AUTH] Google auth success user={user['id']} email={user['email']}")

    return {
        "success": True,
        "access_token": access_token,
        "user": {
            "id": user["id"],
            "email": user["email"],
            "name": user.get("name"),
            "calendar_connected": user.get("calendar_connected", False),
        },
    }


@app.post("/auth/google/extension")
async def google_auth_extension(request: Request):
    """Authenticate with Google access token from Chrome extension.

    Chrome extensions use OAuth implicit flow which returns an access token,
    not an ID token. We verify the access token by calling Google's tokeninfo
    endpoint and then get user info.
    """
    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON body")

    access_token = body.get("access_token")
    email = body.get("email")
    name = body.get("name")
    google_id = body.get("google_id")
    picture = body.get("picture")

    if not access_token or not email:
        raise HTTPException(
            status_code=400, detail="access_token and email are required"
        )

    # Verify the access token with Google
    import httpx

    async with httpx.AsyncClient() as client:
        try:
            token_response = await client.get(
                f"https://www.googleapis.com/oauth2/v3/tokeninfo?access_token={access_token}"
            )
            if token_response.status_code != 200:
                raise HTTPException(
                    status_code=401, detail="Invalid Google access token"
                )

            token_info = token_response.json()

            # Verify the email matches
            if token_info.get("email") != email:
                raise HTTPException(status_code=401, detail="Email mismatch in token")

        except httpx.RequestError:
            raise HTTPException(status_code=401, detail="Failed to verify Google token")

    # Get or create user in database
    user = await db_client.get_or_create_user(
        email=email,
        name=name,
        google_id=google_id,
        picture_url=picture,
    )

    # Create JWT token
    jwt_token = auth_service.create_jwt_token(user["id"], user["email"])

    logger.info(
        f"[AUTH] Google extension auth success user={user['id']} email={user['email']}"
    )

    return {
        "success": True,
        "access_token": jwt_token,
        "user": {
            "id": user["id"],
            "email": user["email"],
            "name": user.get("name"),
            "calendar_connected": user.get("calendar_connected", False),
        },
    }


@app.get("/api/v1/user/profile")
async def get_user_profile(
    request: Request,
    x_user_id: str = Header(None, alias="x-user-id"),
):
    """Get current user profile."""
    user_id = resolve_user_id(request, x_user_id)

    user = await db_client.get_user_by_id(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    return {
        "id": user["id"],
        "email": user["email"],
        "name": user.get("name"),
        "calendar_connected": user.get("calendar_connected", False),
    }


# ============ Google Calendar Endpoints ============


@app.get("/auth/google/calendar/url")
async def get_calendar_auth_url(
    request: Request,
    x_user_id: str = Header(None, alias="x-user-id"),
    redirect_uri: Optional[str] = None,
):
    """Get the URL to authorize Google Calendar access.

    Args:
        redirect_uri: Optional custom redirect URI (for loopback OAuth flow).
                     If not provided, uses the default from config.
    """
    user_id = resolve_user_id(request, x_user_id)

    if not config.GOOGLE_CLIENT_ID:
        raise HTTPException(status_code=500, detail="Google OAuth not configured")

    auth_url = auth_service.get_calendar_auth_url(user_id, redirect_uri=redirect_uri)
    return {"url": auth_url}


@app.get("/auth/google/calendar/callback")
async def calendar_auth_callback(
    request: Request,
    code: str,
    state: str,
):
    """Handle Google Calendar OAuth callback."""
    return await _handle_calendar_callback(request, code, state)


@app.get("/auth/google/callback")
async def calendar_auth_callback_alt(
    request: Request,
    code: str,
    state: str,
):
    """Alternative callback path for Google Calendar OAuth (for localhost redirect)."""
    return await _handle_calendar_callback(request, code, state)


@app.post("/auth/google/calendar/callback")
async def calendar_auth_callback_post(request: Request):
    """Handle Google Calendar OAuth callback from mobile app deep link.

    The mobile app intercepts the deep link (echomind://oauth/callback?code=...&state=...)
    and posts the code and state to this endpoint.
    """
    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON body")

    code = body.get("code")
    state = body.get("state")
    redirect_uri = body.get("redirect_uri", config.GOOGLE_REDIRECT_URI)

    if not code or not state:
        raise HTTPException(status_code=400, detail="code and state are required")

    # Verify state and get user_id
    user_id = auth_service.verify_calendar_state(state)
    if not user_id:
        raise HTTPException(
            status_code=400, detail="Invalid or expired authorization state"
        )

    # Exchange code for tokens using the redirect URI from the request
    tokens = await auth_service.exchange_code_for_tokens(code, redirect_uri)
    if not tokens:
        raise HTTPException(
            status_code=400, detail="Failed to exchange authorization code for tokens"
        )

    # Calculate expiry time
    expires_in = tokens.get("expires_in", 3600)
    expires_at = (datetime.utcnow() + timedelta(seconds=expires_in)).isoformat() + "Z"

    # Save tokens to database
    await db_client.save_user_calendar_tokens(
        user_id=user_id,
        access_token=tokens["access_token"],
        refresh_token=tokens.get("refresh_token"),
        expires_at=expires_at,
    )

    logger.info(f"[CALENDAR] Connected via deep link for user={user_id}")

    return {
        "success": True,
        "message": "Calendar connected successfully",
        "calendar_connected": True,
    }


async def _handle_calendar_callback(request: Request, code: str, state: str):
    """Common handler for calendar OAuth callbacks."""
    # Verify state and get user_id
    user_id = auth_service.verify_calendar_state(state)
    if not user_id:
        return HTMLResponse(
            content="<h1>Error</h1><p>Invalid or expired authorization. Please try again.</p>",
            status_code=400,
        )

    # Build the actual redirect URI that Google used (to match for token exchange)
    # Remove query params to get the base callback URL
    actual_redirect_uri = str(request.url).split("?")[0]

    # Exchange code for tokens (pass actual redirect URI for fallback)
    tokens = await auth_service.exchange_code_for_tokens(code, actual_redirect_uri)
    if not tokens:
        # In local development, offer a localhost -> LAN URL hint for mobile flows.
        full_url = str(request.url)
        if config.LOCAL_IP and (
            "localhost" in full_url or "127.0.0.1" in full_url
        ):
            server_url = full_url.replace("localhost", config.LOCAL_IP).replace(
                "127.0.0.1", config.LOCAL_IP
            )

            return HTMLResponse(
                content=f"""
                <html>
                <head>
                    <title>Complete on Computer</title>
                    <meta name="viewport" content="width=device-width, initial-scale=1">
                    <style>
                        body {{ font-family: -apple-system, sans-serif; padding: 20px; background: #0D0D0D; color: #F5F5F5; }}
                        h1 {{ color: #E9A28B; }}
                        .url-box {{ background: #1A1A1A; padding: 12px; border-radius: 8px; word-break: break-all; margin: 16px 0; font-size: 12px; }}
                        .instructions {{ color: #8A8A8A; line-height: 1.6; }}
                        button {{ background: #E9A28B; color: black; border: none; padding: 12px 24px; border-radius: 8px; font-size: 16px; cursor: pointer; margin-top: 16px; }}
                    </style>
                </head>
                <body>
                    <h1>Almost there!</h1>
                    <p class="instructions">
                        Since you're connecting from your phone, please complete this on your computer:
                    </p>
                    <ol class="instructions">
                        <li>Open this URL on your computer's browser:</li>
                    </ol>
                    <div class="url-box">{server_url}</div>
                    <button onclick="navigator.clipboard.writeText('{server_url}').then(() => alert('Copied!'))">
                        Copy URL
                    </button>
                </body>
                </html>
                """,
                status_code=200,
            )

        logger.error(
            "[CALENDAR] Token exchange failed callback=%s configured_redirect=%s",
            actual_redirect_uri,
            config.GOOGLE_REDIRECT_URI,
        )
        return HTMLResponse(
            content=f"""
            <html>
            <head>
                <title>Calendar Connection Failed</title>
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <style>
                    body {{ font-family: -apple-system, sans-serif; padding: 20px; background: #0D0D0D; color: #F5F5F5; }}
                    h1 {{ color: #ff6b6b; }}
                    .hint {{ color: #BDBDBD; line-height: 1.6; }}
                    .code {{ background: #1A1A1A; padding: 10px; border-radius: 8px; margin: 10px 0; word-break: break-all; }}
                </style>
            </head>
            <body>
                <h1>Calendar connection failed</h1>
                <p class="hint">OAuth redirect URI mismatch is the most common cause.</p>
                <p class="hint">Actual callback URL:</p>
                <div class="code">{actual_redirect_uri}</div>
                <p class="hint">Configured GOOGLE_REDIRECT_URI:</p>
                <div class="code">{config.GOOGLE_REDIRECT_URI}</div>
                <p class="hint">Ensure both URLs are listed in Google Cloud Console Authorized redirect URIs.</p>
            </body>
            </html>
            """,
            status_code=400,
        )

    # Calculate expiry time
    expires_in = tokens.get("expires_in", 3600)
    expires_at = (datetime.utcnow() + timedelta(seconds=expires_in)).isoformat() + "Z"

    # Save tokens to database
    await db_client.save_user_calendar_tokens(
        user_id=user_id,
        access_token=tokens["access_token"],
        refresh_token=tokens.get("refresh_token"),
        expires_at=expires_at,
    )

    logger.info(f"[CALENDAR] Connected for user={user_id}")

    return HTMLResponse(
        content="""
        <html>
        <head>
            <title>Calendar Connected</title>
            <style>
                body { font-family: -apple-system, sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; background: #0D0D0D; color: #F5F5F5; }
                .container { text-align: center; padding: 40px; }
                .icon { font-size: 64px; margin-bottom: 20px; }
                h1 { color: #E9A28B; margin-bottom: 16px; }
                p { color: #8A8A8A; }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="icon">✓</div>
                <h1>Calendar Connected!</h1>
                <p>You can close this window and return to the app.</p>
            </div>
        </body>
        </html>
        """,
        status_code=200,
    )


@app.post("/auth/google/calendar/disconnect")
async def disconnect_calendar(
    request: Request,
    x_user_id: str = Header(None, alias="x-user-id"),
):
    """Disconnect Google Calendar."""
    user_id = resolve_user_id(request, x_user_id)

    await db_client.disconnect_user_calendar(user_id)

    logger.info(f"[CALENDAR] Disconnected for user={user_id}")

    return {"success": True, "message": "Calendar disconnected"}


# ============ Existing Endpoints ============


@app.get("/api/v1/storage/upload-url")
async def get_upload_url(
    request: Request, x_user_id: str = Header(None, alias="x-user-id")
):
    user_id = resolve_user_id(request, x_user_id)
    path = f"{uuid.uuid4().hex}.m4a"
    logger.info(f"[UPLOAD_URL] user={user_id} path={path}")
    try:
        upload_url = await db_client.generate_upload_url(path)
        if not upload_url:
            raise RuntimeError("Failed to generate upload URL")
        logger.info(f"[UPLOAD_URL] success user={user_id} path={path}")
        return {"success": True, "uploadUrl": upload_url, "path": path}
    except Exception as e:
        logger.error(f"Failed to create upload URL: {e}")
        raise HTTPException(status_code=500, detail="Failed to generate upload URL")


@app.get("/api/v1/meetings")
async def get_meetings(
    request: Request,
    limit: int = 8,
    offset: int = 0,
    x_user_id: str = Header(None, alias="x-user-id"),
):
    user_id = resolve_user_id(request, x_user_id)
    safe_limit = limit if limit > 0 else 8
    safe_offset = offset if offset >= 0 else 0
    logger.info(
        f"[MEETINGS_LIST] user={user_id} limit={safe_limit} offset={safe_offset}"
    )
    try:
        meetings = await db_client.get_meetings(
            user_id=user_id, limit=safe_limit, offset=safe_offset
        )
        logger.info(f"[MEETINGS_LIST] success user={user_id} count={len(meetings)}")
        return {"success": True, "data": meetings}
    except Exception as e:
        logger.error(f"Failed to fetch meetings: {e}")
        raise HTTPException(status_code=500, detail="Failed to fetch meetings")


@app.get("/api/v1/meetings/{meeting_id}")
async def get_meeting_detail(
    meeting_id: str,
    request: Request,
    x_user_id: str = Header(None, alias="x-user-id"),
):
    user_id = resolve_user_id(request, x_user_id)
    logger.info(f"[MEETING_DETAIL] user={user_id} meeting={meeting_id}")
    try:
        meeting = await db_client.get_meeting_detail(
            user_id=user_id, meeting_id=meeting_id
        )
        if not meeting:
            raise HTTPException(status_code=404, detail="Meeting not found")
        return {"success": True, "data": meeting}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to fetch meeting detail: {e}")
        raise HTTPException(status_code=500, detail="Failed to fetch meeting details")


@app.post("/api/meetings/process", status_code=202)
async def process_meeting(
    request: Request,
    background_tasks: BackgroundTasks,
    x_user_id: str = Header(None, alias="x-user-id"),
):
    x_user_id = resolve_user_id(request, x_user_id)

    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON body")

    path = body.get("path")
    if not path:
        raise HTTPException(status_code=400, detail="path is required")
    logger.info(f"[PROCESS] start user={x_user_id} path={path}")

    try:
        meeting = await db_client.insert_meeting(x_user_id, path)
    except Exception as e:
        logger.error(f"Failed to create meeting: {e}")
        raise HTTPException(status_code=500, detail="Failed to create meeting")

    logger.info(
        f"[PROCESS] meeting-created id={meeting['id']} path={meeting.get('audio_storage_path')}"
    )

    background_tasks.add_task(
        assembly_service.process_audio_task,
        meeting["id"],
        meeting["audio_storage_path"],
    )
    logger.info(f"[PROCESS] background-queued meeting={meeting['id']}")

    return {
        "success": True,
        "meetingId": meeting["id"],
        "message": "Audio received. Processing in background.",
    }


@app.post("/api/webhooks/assemblyai")
async def assemblyai_webhook(request: Request, background_tasks: BackgroundTasks):
    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON body")

    meeting_id = request.query_params.get("meetingId")
    token = request.query_params.get("token")

    if not meeting_id:
        raise HTTPException(status_code=400, detail="meetingId is required")
    if token != config.WEBHOOK_SECRET:
        raise HTTPException(status_code=401, detail="Unauthorized webhook token")

    transcript_id = body.get("transcript_id") or body.get("id")
    status = body.get("status")

    if not transcript_id:
        raise HTTPException(status_code=400, detail="transcript_id is required")

    logger.info(
        f"[WEBHOOK] received meeting={meeting_id} transcript={transcript_id} status={status}"
    )

    if status not in {"completed", "error"}:
        logger.info(f"Ignoring webhook status '{status}' for meeting {meeting_id}")
        return {"success": True, "message": f"Ignored webhook status: {status}"}

    background_tasks.add_task(
        ai_service.extract_insights_task, meeting_id, transcript_id, status, body
    )

    return {"success": True, "message": "Webhook received"}


# ============ Chat Assistant Endpoint ============


@app.post("/api/v1/chat")
async def chat_with_meetings(
    request: Request,
    x_user_id: str = Header(None, alias="x-user-id"),
):
    """
    RAG-based chat endpoint that answers questions about user's meetings.
    Uses all completed meetings as context to answer time-aware questions.
    """
    user_id = resolve_user_id(request, x_user_id)

    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON body")

    message = body.get("message", "").strip()
    if not message:
        raise HTTPException(status_code=400, detail="message is required")

    logger.info(f"[CHAT] user={user_id} message_length={len(message)}")

    try:
        # Get all completed meetings for this user with full details
        meetings_context = await db_client.get_all_meetings_for_chat(user_id)

        if not meetings_context:
            return {
                "success": True,
                "response": "You don't have any completed meetings yet. Record your first meeting and I'll be able to help you with questions about it!",
                "meetings_searched": 0,
            }

        # Build context from meetings
        context_parts = []
        for meeting in meetings_context:
            meeting_date = meeting.get("created_at", "Unknown date")
            title = meeting.get("title", "Untitled Meeting")
            transcript = meeting.get("transcript_text", "")
            intelligence = meeting.get("intelligence_data", {})

            meeting_context = f"""
=== MEETING: {title} ===
Date: {meeting_date}
"""
            if intelligence:
                if intelligence.get("bottom_line"):
                    meeting_context += f"Summary: {intelligence.get('bottom_line')}\n"
                if intelligence.get("decisions_register"):
                    meeting_context += f"Decisions Made: {', '.join(intelligence.get('decisions_register', []))}\n"
                if intelligence.get("action_matrix"):
                    actions = intelligence.get("action_matrix", [])
                    action_strs = []
                    for a in actions:
                        if isinstance(a, dict):
                            action_str = f"- {a.get('assignee', 'Unknown')}: {a.get('task', 'No task')}"
                            if a.get("deadline"):
                                action_str += f" (Due: {a.get('deadline')})"
                            action_strs.append(action_str)
                    if action_strs:
                        meeting_context += (
                            f"Action Items:\n" + "\n".join(action_strs) + "\n"
                        )
                if intelligence.get("risks_and_blockers"):
                    meeting_context += f"Risks/Blockers: {', '.join(intelligence.get('risks_and_blockers', []))}\n"
                if intelligence.get("key_metrics"):
                    meeting_context += f"Key Metrics: {', '.join(intelligence.get('key_metrics', []))}\n"

            if transcript:
                # Limit transcript length to avoid token limits
                max_transcript_len = 2000
                if len(transcript) > max_transcript_len:
                    transcript = (
                        transcript[:max_transcript_len] + "... [transcript truncated]"
                    )
                meeting_context += f"\nTranscript Excerpt:\n{transcript}\n"

            context_parts.append(meeting_context)

        full_context = "\n\n".join(context_parts)

        # Get current date/time for time-aware responses
        current_datetime = datetime.now().strftime("%A, %B %d, %Y at %I:%M %p")

        # Build the prompt for Gemini
        prompt = f"""You are EchoMind Assistant - a concise, helpful AI that answers questions about the user's meetings.

CURRENT DATE/TIME: {current_datetime}

MEETING DATA:
{full_context}

RESPONSE RULES:
1. Be CONCISE - give the key info in 2-4 sentences max for simple questions
2. Only use info from the meetings above - never make things up
3. Understand time references (yesterday, last week, etc.) relative to current date
4. If info isn't found, say so briefly

FORMATTING RULES (STRICT):
- NEVER use #, *, or any markdown symbols
- For section headers, just write the title followed by a colon on its own line
- Use dash bullets (- ) for lists, keep each item to one line
- Put the most important answer FIRST, then details
- Maximum 3-5 bullet points per section
- No need for headers if the answer is simple (1-2 sentences)

GOOD RESPONSE EXAMPLES:

Simple question example:
Your next meeting with John is on Friday at 2pm, scheduled during your March 15th call.

Question needing detail example:
You have 3 pending action items:
- Budget report due Friday (assigned to you)
- Client proposal draft due next Monday
- Team sync scheduling in progress

Multi-topic example:
Marketing Campaign Discussion (March 15th):
- Decided to launch in Q2
- Budget approved at $50k
- Sarah leading creative

Next Steps:
- Review designs by Friday
- Schedule vendor calls

BAD (never do this):
# Heading
## Subheading  
**bold text**
*italic*
* bullet with asterisk

USER QUESTION: {message}

Give a clear, scannable answer:"""

        # Call Gemini
        import google.generativeai as genai

        genai.configure(api_key=config.GEMINI_API_KEY)
        model = genai.GenerativeModel("gemini-2.5-flash")
        response = model.generate_content(prompt)

        assistant_response = (
            response.text.strip()
            if response.text
            else "I couldn't generate a response. Please try again."
        )

        logger.info(
            f"[CHAT] success user={user_id} meetings_searched={len(meetings_context)}"
        )

        return {
            "success": True,
            "response": assistant_response,
            "meetings_searched": len(meetings_context),
        }

    except Exception as e:
        logger.error(f"[CHAT] failed user={user_id} error={e}")
        raise HTTPException(status_code=500, detail=f"Chat failed: {str(e)}")

# ============ Meeting Groups Endpoints ============


@app.post("/api/v1/groups")
async def create_group(
    request: Request,
    x_user_id: str = Header(None, alias="x-user-id"),
):
    """Create a new meeting group."""
    user_id = resolve_user_id(request, x_user_id)

    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON body")

    name = body.get("name", "").strip()
    if not name:
        raise HTTPException(status_code=400, detail="Group name is required")

    description = body.get("description")

    try:
        group = await db_client.create_group(
            user_id=user_id, name=name, description=description
        )
        logger.info(f"[GROUPS] created group={group['id']} user={user_id}")
        return {"success": True, "data": group}
    except Exception as e:
        logger.error(f"Failed to create group: {e}")
        raise HTTPException(status_code=500, detail="Failed to create group")


@app.get("/api/v1/groups")
async def list_groups(
    request: Request,
    x_user_id: str = Header(None, alias="x-user-id"),
):
    """List all groups for the current user."""
    user_id = resolve_user_id(request, x_user_id)

    try:
        groups = await db_client.get_groups(user_id=user_id)
        logger.info(f"[GROUPS] list user={user_id} count={len(groups)}")
        return {"success": True, "data": groups}
    except Exception as e:
        logger.error(f"Failed to fetch groups: {e}")
        raise HTTPException(status_code=500, detail="Failed to fetch groups")


@app.get("/api/v1/groups/{group_id}")
async def get_group_detail(
    group_id: str,
    request: Request,
    x_user_id: str = Header(None, alias="x-user-id"),
):
    """Get a group with its meetings."""
    user_id = resolve_user_id(request, x_user_id)

    try:
        group = await db_client.get_group_detail(user_id=user_id, group_id=group_id)
        if not group:
            raise HTTPException(status_code=404, detail="Group not found")
        return {"success": True, "data": group}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to fetch group detail: {e}")
        raise HTTPException(status_code=500, detail="Failed to fetch group details")


@app.patch("/api/v1/groups/{group_id}")
async def update_group(
    group_id: str,
    request: Request,
    x_user_id: str = Header(None, alias="x-user-id"),
):
    """Update a group's name or description."""
    user_id = resolve_user_id(request, x_user_id)

    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON body")

    updates = {}
    if "name" in body:
        name = body["name"].strip()
        if not name:
            raise HTTPException(status_code=400, detail="Group name cannot be empty")
        updates["name"] = name
    if "description" in body:
        updates["description"] = body["description"]

    if not updates:
        raise HTTPException(status_code=400, detail="No valid fields to update")

    try:
        group = await db_client.update_group(
            user_id=user_id, group_id=group_id, updates=updates
        )
        if not group:
            raise HTTPException(status_code=404, detail="Group not found")
        logger.info(f"[GROUPS] updated group={group_id} user={user_id}")
        return {"success": True, "data": group}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to update group: {e}")
        raise HTTPException(status_code=500, detail="Failed to update group")


@app.delete("/api/v1/groups/{group_id}")
async def delete_group(
    group_id: str,
    request: Request,
    x_user_id: str = Header(None, alias="x-user-id"),
):
    """Delete a group."""
    user_id = resolve_user_id(request, x_user_id)

    try:
        await db_client.delete_group(user_id=user_id, group_id=group_id)
        logger.info(f"[GROUPS] deleted group={group_id} user={user_id}")
        return {"success": True, "message": "Group deleted"}
    except Exception as e:
        logger.error(f"Failed to delete group: {e}")
        raise HTTPException(status_code=500, detail="Failed to delete group")


@app.post("/api/v1/groups/{group_id}/meetings/{meeting_id}")
async def add_meeting_to_group(
    group_id: str,
    meeting_id: str,
    request: Request,
    x_user_id: str = Header(None, alias="x-user-id"),
):
    """Add a meeting to a group."""
    user_id = resolve_user_id(request, x_user_id)

    # Verify user owns the group
    group = await db_client.get_group_detail(user_id=user_id, group_id=group_id)
    if not group:
        raise HTTPException(status_code=404, detail="Group not found")

    # Verify user owns the meeting
    meeting = await db_client.get_meeting_detail(user_id=user_id, meeting_id=meeting_id)
    if not meeting:
        raise HTTPException(status_code=404, detail="Meeting not found")

    try:
        await db_client.add_meeting_to_group(
            group_id=group_id, meeting_id=meeting_id
        )
        logger.info(
            f"[GROUPS] added meeting={meeting_id} to group={group_id} user={user_id}"
        )
        return {"success": True, "message": "Meeting added to group"}
    except Exception as e:
        logger.error(f"Failed to add meeting to group: {e}")
        raise HTTPException(
            status_code=500, detail="Failed to add meeting to group"
        )


@app.delete("/api/v1/groups/{group_id}/meetings/{meeting_id}")
async def remove_meeting_from_group(
    group_id: str,
    meeting_id: str,
    request: Request,
    x_user_id: str = Header(None, alias="x-user-id"),
):
    """Remove a meeting from a group."""
    user_id = resolve_user_id(request, x_user_id)

    # Verify user owns the group
    group = await db_client.get_group_detail(user_id=user_id, group_id=group_id)
    if not group:
        raise HTTPException(status_code=404, detail="Group not found")

    try:
        await db_client.remove_meeting_from_group(
            group_id=group_id, meeting_id=meeting_id
        )
        logger.info(
            f"[GROUPS] removed meeting={meeting_id} from group={group_id} user={user_id}"
        )
        return {"success": True, "message": "Meeting removed from group"}
    except Exception as e:
        logger.error(f"Failed to remove meeting from group: {e}")
        raise HTTPException(
            status_code=500, detail="Failed to remove meeting from group"
        )


@app.post("/api/v1/groups/{group_id}/chat")
async def chat_with_group_meetings(
    group_id: str,
    request: Request,
    x_user_id: str = Header(None, alias="x-user-id"),
):
    """RAG-based chat endpoint scoped to meetings in a specific group."""
    user_id = resolve_user_id(request, x_user_id)

    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON body")

    message = body.get("message", "").strip()
    if not message:
        raise HTTPException(status_code=400, detail="message is required")

    logger.info(
        f"[GROUP_CHAT] user={user_id} group={group_id} message_length={len(message)}"
    )

    try:
        # Get completed meetings in the group
        meetings_context = await db_client.get_group_meetings_for_chat(
            user_id, group_id
        )

        if not meetings_context:
            return {
                "success": True,
                "response": "This group doesn't have any completed meetings yet. Add meetings to this group and I'll be able to help you with questions about them!",
                "meetings_searched": 0,
            }

        # Build context from meetings (same logic as global chat)
        context_parts = []
        for meeting in meetings_context:
            meeting_date = meeting.get("created_at", "Unknown date")
            title = meeting.get("title", "Untitled Meeting")
            transcript = meeting.get("transcript_text", "")
            intelligence = meeting.get("intelligence_data", {})

            meeting_context = f"""
=== MEETING: {title} ===
Date: {meeting_date}
"""
            if intelligence:
                if intelligence.get("bottom_line"):
                    meeting_context += (
                        f"Summary: {intelligence.get('bottom_line')}\n"
                    )
                if intelligence.get("decisions_register"):
                    meeting_context += f"Decisions Made: {', '.join(intelligence.get('decisions_register', []))}\n"
                if intelligence.get("action_matrix"):
                    actions = intelligence.get("action_matrix", [])
                    action_strs = []
                    for a in actions:
                        if isinstance(a, dict):
                            action_str = f"- {a.get('assignee', 'Unknown')}: {a.get('task', 'No task')}"
                            if a.get("deadline"):
                                action_str += f" (Due: {a.get('deadline')})"
                            action_strs.append(action_str)
                    if action_strs:
                        meeting_context += (
                            f"Action Items:\n" + "\n".join(action_strs) + "\n"
                        )
                if intelligence.get("risks_and_blockers"):
                    meeting_context += f"Risks/Blockers: {', '.join(intelligence.get('risks_and_blockers', []))}\n"
                if intelligence.get("key_metrics"):
                    meeting_context += f"Key Metrics: {', '.join(intelligence.get('key_metrics', []))}\n"

            if transcript:
                max_transcript_len = 2000
                if len(transcript) > max_transcript_len:
                    transcript = (
                        transcript[:max_transcript_len]
                        + "... [transcript truncated]"
                    )
                meeting_context += f"\nTranscript Excerpt:\n{transcript}\n"

            context_parts.append(meeting_context)

        full_context = "\n\n".join(context_parts)
        current_datetime = datetime.now().strftime("%A, %B %d, %Y at %I:%M %p")

        # Get group info for context
        group = await db_client.get_group_detail(user_id, group_id)
        group_name = group.get("name", "Unknown Group") if group else "Unknown Group"

        prompt = f"""You are EchoMind Assistant - a concise, helpful AI that answers questions about meetings in the group "{group_name}".

CURRENT DATE/TIME: {current_datetime}

MEETING DATA (from group "{group_name}"):
{full_context}

RESPONSE RULES:
1. Be CONCISE - give the key info in 2-4 sentences max for simple questions
2. Only use info from the meetings above - never make things up
3. Understand time references (yesterday, last week, etc.) relative to current date
4. If info isn't found, say so briefly
5. You are answering about meetings specifically in this group

FORMATTING RULES (STRICT):
- NEVER use #, *, or any markdown symbols
- For section headers, just write the title followed by a colon on its own line
- Use dash bullets (- ) for lists, keep each item to one line
- Put the most important answer FIRST, then details
- Maximum 3-5 bullet points per section
- No need for headers if the answer is simple (1-2 sentences)

USER QUESTION: {message}

Give a clear, scannable answer:"""

        import google.generativeai as genai

        genai.configure(api_key=config.GEMINI_API_KEY)
        model = genai.GenerativeModel("gemini-2.5-flash")
        response = model.generate_content(prompt)

        assistant_response = (
            response.text.strip()
            if response.text
            else "I couldn't generate a response. Please try again."
        )

        logger.info(
            f"[GROUP_CHAT] success user={user_id} group={group_id} meetings_searched={len(meetings_context)}"
        )

        return {
            "success": True,
            "response": assistant_response,
            "meetings_searched": len(meetings_context),
        }

    except Exception as e:
        logger.error(
            f"[GROUP_CHAT] failed user={user_id} group={group_id} error={e}"
        )
        raise HTTPException(status_code=500, detail=f"Group chat failed: {str(e)}")


if __name__ == "__main__":
    import uvicorn

    port = int(os.getenv("PORT", str(config.BACKEND_PORT)))
    uvicorn.run(app, host="0.0.0.0", port=port)

