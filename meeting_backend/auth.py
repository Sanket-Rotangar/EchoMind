import logging

import httpx
from fastapi import HTTPException, Request

import config

logger = logging.getLogger(__name__)


async def resolve_authenticated_user_id(request: Request) -> str:
    authorization = request.headers.get("authorization", "")
    if not authorization.lower().startswith("bearer "):
        raise HTTPException(
            status_code=401,
            detail="Authorization bearer token is required",
        )

    access_token = authorization[7:].strip()
    if not access_token:
        raise HTTPException(status_code=401, detail="Authorization token is empty")

    user_info_url = f"{config.SUPABASE_URL}/auth/v1/user"
    headers = {
        "apikey": config.SUPABASE_ANON_KEY,
        "Authorization": f"Bearer {access_token}",
    }

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(user_info_url, headers=headers)
    except httpx.HTTPError as error:
        logger.error("Failed to verify Supabase access token: %s", error)
        raise HTTPException(status_code=503, detail="Auth service unavailable") from error

    if response.status_code != 200:
        raise HTTPException(status_code=401, detail="Invalid or expired auth token")

    payload = response.json()
    user_id = payload.get("id")
    if not user_id:
        raise HTTPException(status_code=401, detail="Unable to resolve user from token")

    request.state.user_id = user_id
    return user_id
