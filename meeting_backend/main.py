from fastapi import FastAPI, BackgroundTasks, Request, HTTPException, Header
import config
import db_client
import assembly_service
import ai_service
import logging
import uuid
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="MeetingApp Backend")


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


def resolve_user_id(request: Request, x_user_id: str = None) -> str:
    user_id = x_user_id or request.headers.get("x-user-id") or request.headers.get("user-id")
    if not user_id:
        raise HTTPException(status_code=400, detail="x-user-id header is required")
    return user_id

@app.on_event("startup")
def startup_event():
    config.validate_config()
    logger.info("Configuration validated.")

@app.get("/health")
def health_check():
    return {"status": "ok", "message": "Render health ping received"}


@app.get("/api/v1/storage/upload-url")
async def get_upload_url(request: Request, x_user_id: str = Header(None, alias="x-user-id")):
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
    logger.info(f"[MEETINGS_LIST] user={user_id} limit={safe_limit} offset={safe_offset}")
    try:
        meetings = await db_client.get_meetings(user_id=user_id, limit=safe_limit, offset=safe_offset)
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
        meeting = await db_client.get_meeting_detail(user_id=user_id, meeting_id=meeting_id)
        if not meeting:
            raise HTTPException(status_code=404, detail="Meeting not found")
        return {"success": True, "data": meeting}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to fetch meeting detail: {e}")
        raise HTTPException(status_code=500, detail="Failed to fetch meeting details")

@app.post("/api/meetings/process", status_code=202)
async def process_meeting(request: Request, background_tasks: BackgroundTasks, x_user_id: str = Header(None, alias="x-user-id")):
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

    logger.info(f"[PROCESS] meeting-created id={meeting['id']} path={meeting.get('audio_storage_path')}")
    
    background_tasks.add_task(assembly_service.process_audio_task, meeting["id"], meeting["audio_storage_path"])
    logger.info(f"[PROCESS] background-queued meeting={meeting['id']}")
    
    return {
        "success": True,
        "meetingId": meeting["id"],
        "message": "Audio received. Processing in background."
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

    logger.info(f"[WEBHOOK] received meeting={meeting_id} transcript={transcript_id} status={status}")

    if status not in {"completed", "error"}:
        logger.info(f"Ignoring webhook status '{status}' for meeting {meeting_id}")
        return {"success": True, "message": f"Ignored webhook status: {status}"}
        
    background_tasks.add_task(ai_service.extract_insights_task, meeting_id, transcript_id, status, body)
    
    return {"success": True, "message": "Webhook received"}
