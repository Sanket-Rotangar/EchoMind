import httpx
import config
from typing import Dict, Any, List
from urllib.parse import quote
from urllib.parse import urlsplit, urlunsplit, parse_qsl, urlencode
import logging

logger = logging.getLogger(__name__)


def _supabase_headers(prefer: str = "") -> Dict[str, str]:
    headers = {
        "apikey": config.SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {config.SUPABASE_SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
    }
    if prefer:
        headers["Prefer"] = prefer
    return headers


def _postgrest_url(path: str) -> str:
    return f"{config.SUPABASE_URL}/rest/v1/{path.lstrip('/')}"


def _normalize_signed_storage_url(signed_path: str) -> str:
    normalized = str(signed_path or "")
    if not normalized:
        return ""
    if normalized.startswith("http"):
        return normalized
    if normalized.startswith("/storage/v1"):
        return f"{config.SUPABASE_URL}{normalized}"
    if normalized.startswith("/object"):
        return f"{config.SUPABASE_URL}/storage/v1{normalized}"
    if normalized.startswith("object"):
        return f"{config.SUPABASE_URL}/storage/v1/{normalized}"
    return f"{config.SUPABASE_URL}/storage/v1/{normalized.lstrip('/')}"


def _ensure_single_token(url: str, token_override: str = "") -> str:
    parts = urlsplit(url)
    query_pairs = parse_qsl(parts.query, keep_blank_values=True)
    existing_token = ""
    filtered_pairs = []
    for key, value in query_pairs:
        if key == "token" and not existing_token:
            existing_token = value
        if key != "token":
            filtered_pairs.append((key, value))

    token_value = token_override or existing_token
    if token_value:
        filtered_pairs.append(("token", token_value))

    normalized_query = urlencode(filtered_pairs)
    return urlunsplit((parts.scheme, parts.netloc, parts.path, normalized_query, parts.fragment))


async def insert_meeting(user_id: str, path: str) -> Dict[str, Any]:
    logger.info(f"[DB] insert meeting user={user_id} path={path}")
    url = _postgrest_url("meetings")
    payload = {
        "user_id": user_id,
        "title": "Processing Meeting...",
        "status": "processing",
        "audio_storage_path": path,
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(
            url,
            headers=_supabase_headers(prefer="return=representation"),
            json=payload,
        )

        if response.status_code >= 400:
            body_text = response.text
            if response.status_code == 409 or "23505" in body_text or "unique_user_audio_path" in body_text:
                logger.warning(f"[DB] duplicate meeting detected user={user_id} path={path}, returning existing row")
                query_url = _postgrest_url(
                    f"meetings?user_id=eq.{quote(user_id, safe='')}&audio_storage_path=eq.{quote(path, safe='')}&select=id,audio_storage_path&order=created_at.desc&limit=1"
                )
                existing = await client.get(query_url, headers=_supabase_headers())
                existing.raise_for_status()
                rows = existing.json()
                if rows:
                    return rows[0]
            response.raise_for_status()

        rows = response.json()
        if not rows:
            raise RuntimeError("Failed to create meeting row")
        logger.info(f"[DB] insert meeting success id={rows[0].get('id')}")
        return rows[0]


async def update_meeting(meeting_id: str, payload: Dict[str, Any]):
    logger.info(f"[DB] update meeting id={meeting_id} fields={list(payload.keys())}")
    url = _postgrest_url(f"meetings?id=eq.{quote(meeting_id, safe='')}")
    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.patch(
            url,
            headers=_supabase_headers(prefer="return=representation"),
            json=payload,
        )
        if response.status_code >= 400:
            logger.error(
                "[DB] update meeting failed id=%s status=%s response=%s",
                meeting_id,
                response.status_code,
                response.text,
            )
            response.raise_for_status()
        return response.json()


async def replace_action_items(meeting_id: str, items: List[Dict[str, Any]]):
    logger.info(f"[DB] replace action_items meeting={meeting_id} count={len(items)}")
    delete_url = _postgrest_url(f"action_items?meeting_id=eq.{quote(meeting_id, safe='')}")
    async with httpx.AsyncClient(timeout=30.0) as client:
        delete_response = await client.delete(delete_url, headers=_supabase_headers())
        delete_response.raise_for_status()

        if items:
            insert_url = _postgrest_url("action_items")
            insert_response = await client.post(
                insert_url,
                headers=_supabase_headers(prefer="return=minimal"),
                json=items,
            )
            insert_response.raise_for_status()


async def generate_signed_url(path: str) -> str:
    logger.info(f"[STORAGE] generate download signed url path={path}")
    url = f"{config.SUPABASE_URL}/storage/v1/object/sign/{config.SUPABASE_BUCKET}/{quote(path, safe='')}"
    body = {"expiresIn": 3600}
    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(url, headers=_supabase_headers(), json=body)
        response.raise_for_status()
        data = response.json()
        signed_path = data.get("signedURL") or data.get("signedUrl")
        logger.info(f"[STORAGE] download signed url generated path={path}")
        return _normalize_signed_storage_url(signed_path)


async def generate_upload_url(path: str) -> str:
    logger.info(f"[STORAGE] generate upload signed url path={path}")
    url = f"{config.SUPABASE_URL}/storage/v1/object/upload/sign/{config.SUPABASE_BUCKET}/{quote(path, safe='')}"
    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(url, headers=_supabase_headers(), json={"upsert": False})
        response.raise_for_status()
        data = response.json()

        signed_path = data.get("signedURL") or data.get("signedUrl")
        if signed_path:
            logger.info(f"[STORAGE] upload signed url generated path={path} mode=signedPath")
            normalized = _normalize_signed_storage_url(signed_path)
            return _ensure_single_token(normalized)

        relative_url = data.get("url")
        token = data.get("token")
        if relative_url:
            base = _normalize_signed_storage_url(str(relative_url))
            base = _ensure_single_token(base, str(token or ""))
            logger.info(f"[STORAGE] upload signed url generated path={path} mode=url")
            return base

        logger.error(f"[STORAGE] upload signed url missing expected keys path={path} keys={list(data.keys())}")
        return ""


async def get_meetings(user_id: str, limit: int = 8, offset: int = 0) -> List[Dict[str, Any]]:
    logger.info(f"[DB] list meetings user={user_id} limit={limit} offset={offset}")
    end = offset + limit - 1
    url = _postgrest_url(
        f"meetings?user_id=eq.{quote(user_id, safe='')}&select=id,title,status,created_at&order=created_at.desc&offset={offset}&limit={limit}"
    )
    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.get(url, headers=_supabase_headers())
        response.raise_for_status()
        return response.json() or []


async def get_meeting_detail(user_id: str, meeting_id: str) -> Dict[str, Any]:
    logger.info(f"[DB] meeting detail user={user_id} meeting={meeting_id}")
    url = _postgrest_url(
        f"meetings?id=eq.{quote(meeting_id, safe='')}&user_id=eq.{quote(user_id, safe='')}&select=*,action_items(*)&limit=1"
    )
    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.get(url, headers=_supabase_headers())
        response.raise_for_status()
        rows = response.json() or []
        if not rows:
            return {}
        return rows[0]
