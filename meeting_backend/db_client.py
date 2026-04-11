import httpx
import config
from typing import Dict, Any, List, Optional
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
    return urlunsplit(
        (parts.scheme, parts.netloc, parts.path, normalized_query, parts.fragment)
    )


async def insert_meeting(user_id: str, path: str) -> Dict[str, Any]:
    logger.info(f"[DB] insert meeting user={user_id} path={path}")
    url = _postgrest_url("meetings")
    payload = {
        "user_id": user_id,
        "title": "Processing Meeting...",
        "status": "uploaded",
        "audio_storage_path": path,
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(
            url,
            headers=_supabase_headers(prefer="return=representation"),
            json=payload,
        )

        if response.status_code >= 400:
            logger.error(
                "[DB] insert meeting failed user=%s path=%s status=%s response=%s",
                user_id,
                path,
                response.status_code,
                response.text,
            )
            body_text = response.text
            if (
                response.status_code == 409
                or "23505" in body_text
                or "unique_user_audio_path" in body_text
            ):
                logger.warning(
                    f"[DB] duplicate meeting detected user={user_id} path={path}, returning existing row"
                )
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


async def insert_meeting_event(
    meeting_id: str, stage: str, details: Optional[Dict[str, Any]] = None
):
    payload = {
        "meeting_id": meeting_id,
        "stage": stage,
        "details": details or {},
    }
    url = _postgrest_url("meeting_state_events")
    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(
            url,
            headers=_supabase_headers(prefer="return=minimal"),
            json=payload,
        )
        if response.status_code >= 400:
            logger.error(
                "[DB] insert meeting event failed meeting=%s stage=%s status=%s response=%s",
                meeting_id,
                stage,
                response.status_code,
                response.text,
            )
            response.raise_for_status()
        logger.info(
            "[DB] meeting event inserted meeting=%s stage=%s", meeting_id, stage
        )


async def transition_meeting_state(
    meeting_id: str,
    status: str,
    details: Optional[Dict[str, Any]] = None,
    extra_updates: Optional[Dict[str, Any]] = None,
):
    logger.info(
        "[PIPELINE][STATE] transition-start meeting=%s status=%s detailsKeys=%s updateKeys=%s",
        meeting_id,
        status,
        sorted(list((details or {}).keys())),
        sorted(list((extra_updates or {}).keys())),
    )
    payload = {"status": status}
    if extra_updates:
        payload.update(extra_updates)
    await update_meeting(meeting_id, payload)
    await insert_meeting_event(meeting_id, status, details)
    logger.info(
        "[PIPELINE][STATE] transition-done meeting=%s status=%s", meeting_id, status
    )


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
    delete_url = _postgrest_url(
        f"action_items?meeting_id=eq.{quote(meeting_id, safe='')}"
    )
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
        response = await client.post(
            url, headers=_supabase_headers(), json={"upsert": False}
        )
        response.raise_for_status()
        data = response.json()

        signed_path = data.get("signedURL") or data.get("signedUrl")
        if signed_path:
            logger.info(
                f"[STORAGE] upload signed url generated path={path} mode=signedPath"
            )
            normalized = _normalize_signed_storage_url(signed_path)
            return _ensure_single_token(normalized)

        relative_url = data.get("url")
        token = data.get("token")
        if relative_url:
            base = _normalize_signed_storage_url(str(relative_url))
            base = _ensure_single_token(base, str(token or ""))
            logger.info(f"[STORAGE] upload signed url generated path={path} mode=url")
            return base

        logger.error(
            f"[STORAGE] upload signed url missing expected keys path={path} keys={list(data.keys())}"
        )
        return ""


async def get_meetings(
    user_id: str, limit: int = 8, offset: int = 0
) -> List[Dict[str, Any]]:
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
        f"meetings?id=eq.{quote(meeting_id, safe='')}&user_id=eq.{quote(user_id, safe='')}&select=*,action_items(*),meeting_state_events(*)&limit=1"
    )
    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.get(url, headers=_supabase_headers())
        response.raise_for_status()
        rows = response.json() or []
        if not rows:
            return {}
        return rows[0]


async def get_meeting_by_id(meeting_id: str) -> Dict[str, Any]:
    logger.info(f"[DB] meeting by id meeting={meeting_id}")
    url = _postgrest_url(
        f"meetings?id=eq.{quote(meeting_id, safe='')}&select=*&limit=1"
    )
    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.get(url, headers=_supabase_headers())
        response.raise_for_status()
        rows = response.json() or []
        if not rows:
            return {}
        return rows[0]


# ============ User Management ============


async def get_user_by_email(email: str) -> Optional[Dict[str, Any]]:
    """Get a user by email."""
    logger.info(f"[DB] get user by email={email}")
    url = _postgrest_url(f"users?email=eq.{quote(email, safe='')}&limit=1")
    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.get(url, headers=_supabase_headers())
        response.raise_for_status()
        rows = response.json() or []
        return rows[0] if rows else None


async def get_user_by_id(user_id: str) -> Optional[Dict[str, Any]]:
    """Get a user by ID."""
    logger.info(f"[DB] get user by id={user_id}")
    url = _postgrest_url(f"users?id=eq.{quote(user_id, safe='')}&limit=1")
    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.get(url, headers=_supabase_headers())
        response.raise_for_status()
        rows = response.json() or []
        return rows[0] if rows else None


async def create_user(
    email: str,
    name: Optional[str] = None,
    google_id: Optional[str] = None,
    picture_url: Optional[str] = None,
) -> Dict[str, Any]:
    """Create a new user."""
    logger.info(f"[DB] create user email={email}")
    url = _postgrest_url("users")
    payload = {
        "email": email,
        "name": name,
        "google_id": google_id,
        "picture_url": picture_url,
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(
            url,
            headers=_supabase_headers(prefer="return=representation"),
            json=payload,
        )
        response.raise_for_status()
        rows = response.json()
        if not rows:
            raise RuntimeError("Failed to create user")
        logger.info(f"[DB] user created id={rows[0].get('id')}")
        return rows[0]


async def update_user(user_id: str, updates: Dict[str, Any]) -> Dict[str, Any]:
    """Update a user."""
    logger.info(f"[DB] update user id={user_id} fields={list(updates.keys())}")
    url = _postgrest_url(f"users?id=eq.{quote(user_id, safe='')}")
    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.patch(
            url,
            headers=_supabase_headers(prefer="return=representation"),
            json=updates,
        )
        response.raise_for_status()
        rows = response.json()
        return rows[0] if rows else {}


async def get_or_create_user(
    email: str,
    name: Optional[str] = None,
    google_id: Optional[str] = None,
    picture_url: Optional[str] = None,
) -> Dict[str, Any]:
    """Get existing user or create new one."""
    user = await get_user_by_email(email)

    if user:
        # Update user info if needed
        updates = {}
        if name and user.get("name") != name:
            updates["name"] = name
        if google_id and user.get("google_id") != google_id:
            updates["google_id"] = google_id
        if picture_url and user.get("picture_url") != picture_url:
            updates["picture_url"] = picture_url

        if updates:
            user = await update_user(user["id"], updates)

        return user

    return await create_user(email, name, google_id, picture_url)


async def save_user_calendar_tokens(
    user_id: str,
    access_token: str,
    refresh_token: Optional[str],
    expires_at: Optional[str],
) -> Dict[str, Any]:
    """Save Google Calendar tokens for a user."""
    logger.info(f"[DB] save calendar tokens user={user_id}")

    calendar_tokens = {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "expires_at": expires_at,
    }

    return await update_user(
        user_id,
        {
            "calendar_connected": True,
            "calendar_tokens": calendar_tokens,
        },
    )


async def get_user_calendar_tokens(user_id: str) -> Optional[Dict[str, Any]]:
    """Get a user's calendar tokens."""
    user = await get_user_by_id(user_id)
    if not user:
        return None
    return user.get("calendar_tokens")


async def disconnect_user_calendar(user_id: str) -> Dict[str, Any]:
    """Disconnect a user's calendar."""
    logger.info(f"[DB] disconnect calendar user={user_id}")
    return await update_user(
        user_id,
        {
            "calendar_connected": False,
            "calendar_tokens": None,
        },
    )


async def create_user_with_password(
    email: str,
    name: str,
    password_hash: str,
) -> Dict[str, Any]:
    """Create a new user with email and password."""
    logger.info(f"[DB] create user with password email={email}")
    url = _postgrest_url("users")
    payload = {
        "email": email,
        "name": name,
        "password_hash": password_hash,
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(
            url,
            headers=_supabase_headers(prefer="return=representation"),
            json=payload,
        )
        if response.status_code >= 400:
            logger.error(
                "[DB] create user with password failed email=%s status=%s response=%s",
                email,
                response.status_code,
                response.text,
            )
            response.raise_for_status()
        rows = response.json()
        if not rows:
            raise RuntimeError("Failed to create user")
        logger.info(f"[DB] user with password created id={rows[0].get('id')}")
        return rows[0]


async def get_all_meetings_for_chat(user_id: str) -> List[Dict[str, Any]]:
    """Get all completed meetings for a user with full context for RAG chat."""
    logger.info(f"[DB] get all meetings for chat user={user_id}")
    url = _postgrest_url(
        f"meetings?user_id=eq.{quote(user_id, safe='')}&status=eq.completed&select=id,title,created_at,transcript_text,intelligence_data&order=created_at.desc&limit=50"
    )
    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.get(url, headers=_supabase_headers())
        response.raise_for_status()
        meetings = response.json() or []
        logger.info(f"[DB] chat context loaded user={user_id} meetings={len(meetings)}")
        return meetings


# ============ Meeting Groups ============


async def create_group(
    user_id: str, name: str, description: Optional[str] = None
) -> Dict[str, Any]:
    """Create a new meeting group."""
    logger.info(f"[DB] create group user={user_id} name={name}")
    url = _postgrest_url("meeting_groups")
    payload = {
        "user_id": user_id,
        "name": name,
        "description": description,
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(
            url,
            headers=_supabase_headers(prefer="return=representation"),
            json=payload,
        )
        if response.status_code >= 400:
            logger.error(
                "[DB] create group failed user=%s status=%s response=%s",
                user_id,
                response.status_code,
                response.text,
            )
            response.raise_for_status()
        rows = response.json()
        if not rows:
            raise RuntimeError("Failed to create group")
        logger.info(f"[DB] group created id={rows[0].get('id')}")
        return rows[0]


async def get_groups(user_id: str) -> List[Dict[str, Any]]:
    """Get all groups for a user with meeting count."""
    logger.info(f"[DB] list groups user={user_id}")
    url = _postgrest_url(
        f"meeting_groups?user_id=eq.{quote(user_id, safe='')}"
        f"&select=id,name,description,created_at,updated_at,meeting_group_members(count)"
        f"&order=created_at.desc"
    )
    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.get(
            url, headers=_supabase_headers(prefer="count=exact")
        )
        response.raise_for_status()
        groups = response.json() or []

        # Flatten the count from the nested relationship
        for group in groups:
            members = group.pop("meeting_group_members", [])
            if members and isinstance(members, list) and len(members) > 0:
                group["meeting_count"] = members[0].get("count", 0)
            else:
                group["meeting_count"] = 0

        logger.info(f"[DB] groups loaded user={user_id} count={len(groups)}")
        return groups


async def get_group_detail(user_id: str, group_id: str) -> Optional[Dict[str, Any]]:
    """Get a group with its meetings."""
    logger.info(f"[DB] group detail user={user_id} group={group_id}")
    # First get the group
    group_url = _postgrest_url(
        f"meeting_groups?id=eq.{quote(group_id, safe='')}"
        f"&user_id=eq.{quote(user_id, safe='')}"
        f"&select=*"
        f"&limit=1"
    )
    async with httpx.AsyncClient(timeout=30.0) as client:
        group_response = await client.get(group_url, headers=_supabase_headers())
        group_response.raise_for_status()
        groups = group_response.json() or []
        if not groups:
            return None

        group = groups[0]

        # Get meetings in this group via the join table
        members_url = _postgrest_url(
            f"meeting_group_members?group_id=eq.{quote(group_id, safe='')}"
            f"&select=meeting_id,added_at,meetings(id,title,status,created_at)"
            f"&order=added_at.desc"
        )
        members_response = await client.get(members_url, headers=_supabase_headers())
        members_response.raise_for_status()
        members = members_response.json() or []

        # Flatten: extract the meeting from nested join
        meetings = []
        for member in members:
            meeting_data = member.get("meetings")
            if meeting_data:
                meeting_data["added_at"] = member.get("added_at")
                meetings.append(meeting_data)

        group["meetings"] = meetings
        group["meeting_count"] = len(meetings)
        return group


async def update_group(
    user_id: str, group_id: str, updates: Dict[str, Any]
) -> Optional[Dict[str, Any]]:
    """Update a group (only if owned by user)."""
    logger.info(f"[DB] update group user={user_id} group={group_id}")
    url = _postgrest_url(
        f"meeting_groups?id=eq.{quote(group_id, safe='')}"
        f"&user_id=eq.{quote(user_id, safe='')}"
    )
    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.patch(
            url,
            headers=_supabase_headers(prefer="return=representation"),
            json=updates,
        )
        if response.status_code >= 400:
            logger.error(
                "[DB] update group failed group=%s status=%s response=%s",
                group_id,
                response.status_code,
                response.text,
            )
            response.raise_for_status()
        rows = response.json()
        return rows[0] if rows else None


async def delete_group(user_id: str, group_id: str) -> bool:
    """Delete a group (only if owned by user). Cascade deletes members."""
    logger.info(f"[DB] delete group user={user_id} group={group_id}")
    url = _postgrest_url(
        f"meeting_groups?id=eq.{quote(group_id, safe='')}"
        f"&user_id=eq.{quote(user_id, safe='')}"
    )
    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.delete(url, headers=_supabase_headers())
        if response.status_code >= 400:
            logger.error(
                "[DB] delete group failed group=%s status=%s response=%s",
                group_id,
                response.status_code,
                response.text,
            )
            response.raise_for_status()
        return True


async def add_meeting_to_group(group_id: str, meeting_id: str) -> Dict[str, Any]:
    """Add a meeting to a group."""
    logger.info(f"[DB] add meeting to group group={group_id} meeting={meeting_id}")
    url = _postgrest_url("meeting_group_members")
    payload = {
        "group_id": group_id,
        "meeting_id": meeting_id,
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(
            url,
            headers=_supabase_headers(prefer="return=representation"),
            json=payload,
        )
        if response.status_code >= 400:
            body_text = response.text
            # Handle duplicate gracefully
            if (
                response.status_code == 409
                or "23505" in body_text
                or "unique_group_meeting" in body_text
            ):
                logger.info(
                    f"[DB] meeting already in group group={group_id} meeting={meeting_id}"
                )
                return {"group_id": group_id, "meeting_id": meeting_id}
            logger.error(
                "[DB] add meeting to group failed status=%s response=%s",
                response.status_code,
                body_text,
            )
            response.raise_for_status()
        rows = response.json()
        return rows[0] if rows else {"group_id": group_id, "meeting_id": meeting_id}


async def remove_meeting_from_group(group_id: str, meeting_id: str) -> bool:
    """Remove a meeting from a group."""
    logger.info(f"[DB] remove meeting from group group={group_id} meeting={meeting_id}")
    url = _postgrest_url(
        f"meeting_group_members?group_id=eq.{quote(group_id, safe='')}"
        f"&meeting_id=eq.{quote(meeting_id, safe='')}"
    )
    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.delete(url, headers=_supabase_headers())
        if response.status_code >= 400:
            logger.error(
                "[DB] remove meeting from group failed status=%s response=%s",
                response.status_code,
                response.text,
            )
            response.raise_for_status()
        return True


async def get_group_meetings_for_chat(
    user_id: str, group_id: str
) -> List[Dict[str, Any]]:
    """Get all completed meetings in a group for RAG chat."""
    logger.info(f"[DB] get group meetings for chat user={user_id} group={group_id}")

    # Verify group ownership
    group_url = _postgrest_url(
        f"meeting_groups?id=eq.{quote(group_id, safe='')}"
        f"&user_id=eq.{quote(user_id, safe='')}"
        f"&select=id"
        f"&limit=1"
    )
    async with httpx.AsyncClient(timeout=30.0) as client:
        group_response = await client.get(group_url, headers=_supabase_headers())
        group_response.raise_for_status()
        if not (group_response.json() or []):
            return []

        # Get meeting IDs in the group
        members_url = _postgrest_url(
            f"meeting_group_members?group_id=eq.{quote(group_id, safe='')}"
            f"&select=meeting_id"
        )
        members_response = await client.get(members_url, headers=_supabase_headers())
        members_response.raise_for_status()
        members = members_response.json() or []

        if not members:
            return []

        meeting_ids = [m["meeting_id"] for m in members]

        # Get completed meetings with full context
        # PostgREST in() filter
        ids_csv = ",".join(meeting_ids)
        meetings_url = _postgrest_url(
            f"meetings?id=in.({ids_csv})"
            f"&status=eq.completed"
            f"&select=id,title,created_at,transcript_text,intelligence_data"
            f"&order=created_at.desc"
        )
        meetings_response = await client.get(
            meetings_url, headers=_supabase_headers()
        )
        meetings_response.raise_for_status()
        meetings = meetings_response.json() or []
        logger.info(
            f"[DB] group chat context loaded group={group_id} meetings={len(meetings)}"
        )
        return meetings

