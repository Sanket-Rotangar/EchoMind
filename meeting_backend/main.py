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
from datetime import datetime, timedelta
from typing import Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="EchoMind Backend")

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
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
        # If token exchange failed, it might be because we're on the phone
        # and the redirect_uri doesn't match. Show helpful message.
        full_url = str(request.url)
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
                <p class="instructions" style="margin-top: 24px;">
                    Or copy the URL above, paste it in your computer's browser, and replace 'localhost' with '{config.LOCAL_IP}'
                </p>
            </body>
            </html>
            """,
            status_code=200,
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


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)
