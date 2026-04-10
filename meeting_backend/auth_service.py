import httpx
import config
import logging
import jwt
import json
import hashlib
import secrets
import re
from urllib.parse import urlencode
from datetime import datetime, timedelta
from typing import Optional, Dict, Any, Tuple

# Try to import google auth, but make it optional for email/password auth
try:
    from google.oauth2 import id_token
    from google.auth.transport import requests as google_requests

    GOOGLE_AUTH_AVAILABLE = True
except ImportError:
    GOOGLE_AUTH_AVAILABLE = False
    id_token = None
    google_requests = None

logger = logging.getLogger(__name__)

# Google OAuth URLs
GOOGLE_AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token"
GOOGLE_USERINFO_URL = "https://www.googleapis.com/oauth2/v2/userinfo"

# Calendar scopes
CALENDAR_SCOPES = [
    "https://www.googleapis.com/auth/calendar.events",
    "https://www.googleapis.com/auth/calendar.readonly",
]


def create_jwt_token(user_id: str, email: str) -> str:
    """Create a JWT token for the user."""
    payload = {
        "sub": user_id,
        "email": email,
        "iat": datetime.utcnow(),
        "exp": datetime.utcnow() + timedelta(hours=config.JWT_EXPIRY_HOURS),
    }
    return jwt.encode(payload, config.JWT_SECRET, algorithm=config.JWT_ALGORITHM)


def verify_jwt_token(token: str) -> Optional[Dict[str, Any]]:
    """Verify a JWT token and return the payload."""
    try:
        payload = jwt.decode(
            token, config.JWT_SECRET, algorithms=[config.JWT_ALGORITHM]
        )
        return payload
    except jwt.ExpiredSignatureError:
        logger.warning("JWT token expired")
        return None
    except jwt.InvalidTokenError as e:
        logger.warning(f"Invalid JWT token: {e}")
        return None


async def verify_google_id_token(id_token_str: str) -> Optional[Dict[str, Any]]:
    """Verify a Google ID token from mobile app sign-in."""
    if not GOOGLE_AUTH_AVAILABLE:
        logger.error(
            "Google auth libraries not installed. Install google-auth package."
        )
        return None

    # Try to verify with Android client ID first, then Web client ID
    client_ids_to_try = []
    if config.GOOGLE_ANDROID_CLIENT_ID:
        client_ids_to_try.append(config.GOOGLE_ANDROID_CLIENT_ID)
    if config.GOOGLE_CLIENT_ID:
        client_ids_to_try.append(config.GOOGLE_CLIENT_ID)

    if not client_ids_to_try:
        logger.error("No Google Client IDs configured")
        return None

    for client_id in client_ids_to_try:
        try:
            idinfo = id_token.verify_oauth2_token(
                id_token_str, google_requests.Request(), client_id
            )

            # Verify the issuer
            if idinfo["iss"] not in [
                "accounts.google.com",
                "https://accounts.google.com",
            ]:
                logger.error("Invalid issuer in Google ID token")
                continue

            logger.info(f"Google ID token verified with client_id: {client_id[:20]}...")
            return {
                "google_id": idinfo.get("sub"),
                "email": idinfo.get("email"),
                "name": idinfo.get("name"),
                "picture": idinfo.get("picture"),
                "email_verified": idinfo.get("email_verified", False),
            }
        except Exception as e:
            logger.warning(
                f"Token verification failed with client {client_id[:20]}...: {e}"
            )
            continue

    logger.error("Google ID token verification failed with all client IDs")
    return None


def get_calendar_auth_url(user_id: str, redirect_uri: Optional[str] = None) -> str:
    """Generate the Google OAuth URL for calendar access.

    Args:
        user_id: The user ID to encode in the state parameter.
        redirect_uri: Optional custom redirect URI (for loopback OAuth flow).
                     If not provided, uses the default from config.
    """
    state = jwt.encode(
        {"user_id": user_id, "purpose": "calendar"},
        config.JWT_SECRET,
        algorithm=config.JWT_ALGORITHM,
    )

    # Use provided redirect_uri or fall back to config
    actual_redirect_uri = redirect_uri or config.GOOGLE_REDIRECT_URI

    params = {
        "client_id": config.GOOGLE_CLIENT_ID,
        "redirect_uri": actual_redirect_uri,
        "response_type": "code",
        "scope": " ".join(CALENDAR_SCOPES),
        "access_type": "offline",
        "prompt": "consent",
        "state": state,
    }

    # Use urlencode to properly encode all parameters
    query_string = urlencode(params)
    return f"{GOOGLE_AUTH_URL}?{query_string}"


async def exchange_code_for_tokens(
    code: str, actual_redirect_uri: Optional[str] = None
) -> Optional[Dict[str, Any]]:
    """Exchange authorization code for access and refresh tokens.

    Args:
        code: The authorization code from Google
        actual_redirect_uri: The redirect URI that was actually used (optional, for fallback)
    """
    # Try the configured redirect URI first, then fallback to alternatives
    redirect_uris_to_try = [config.GOOGLE_REDIRECT_URI]

    # If actual_redirect_uri provided and different, try it first
    if actual_redirect_uri and actual_redirect_uri not in redirect_uris_to_try:
        redirect_uris_to_try.insert(0, actual_redirect_uri)

    # Optionally try additional redirect URIs (typically local dev loopback).
    for variant in config.GOOGLE_FALLBACK_REDIRECT_URIS:
        if variant not in redirect_uris_to_try:
            redirect_uris_to_try.append(variant)

    for redirect_uri in redirect_uris_to_try:
        try:
            logger.info(f"Attempting token exchange with redirect_uri: {redirect_uri}")
            async with httpx.AsyncClient() as client:
                response = await client.post(
                    GOOGLE_TOKEN_URL,
                    data={
                        "client_id": config.GOOGLE_CLIENT_ID,
                        "client_secret": config.GOOGLE_CLIENT_SECRET,
                        "code": code,
                        "grant_type": "authorization_code",
                        "redirect_uri": redirect_uri,
                    },
                )

                if response.status_code == 200:
                    logger.info(
                        f"Token exchange successful with redirect_uri: {redirect_uri}"
                    )
                    return response.json()
                else:
                    logger.warning(
                        f"Token exchange failed with {redirect_uri}: {response.text}"
                    )
        except Exception as e:
            logger.warning(f"Token exchange error with {redirect_uri}: {e}")
            continue

    logger.error("Token exchange failed with all redirect URIs")
    return None


async def refresh_access_token(refresh_token: str) -> Optional[Dict[str, Any]]:
    """Refresh an expired access token."""
    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(
                GOOGLE_TOKEN_URL,
                data={
                    "client_id": config.GOOGLE_CLIENT_ID,
                    "client_secret": config.GOOGLE_CLIENT_SECRET,
                    "refresh_token": refresh_token,
                    "grant_type": "refresh_token",
                },
            )

            if response.status_code != 200:
                logger.error(f"Token refresh failed: {response.text}")
                return None

            return response.json()
    except Exception as e:
        logger.error(f"Error refreshing token: {e}")
        return None


def verify_calendar_state(state: str) -> Optional[str]:
    """Verify the state parameter and return the user_id."""
    try:
        payload = jwt.decode(
            state, config.JWT_SECRET, algorithms=[config.JWT_ALGORITHM]
        )
        if payload.get("purpose") != "calendar":
            return None
        return payload.get("user_id")
    except Exception as e:
        logger.error(f"Error verifying calendar state: {e}")
        return None


# ==================== Email/Password Authentication ====================


def hash_password(password: str, salt: Optional[str] = None) -> Tuple[str, str]:
    """
    Hash a password using PBKDF2-SHA256 with a random salt.
    Returns (hash, salt) tuple.
    """
    if salt is None:
        salt = secrets.token_hex(32)

    # Use PBKDF2 with SHA256, 100000 iterations
    password_hash = hashlib.pbkdf2_hmac(
        "sha256", password.encode("utf-8"), salt.encode("utf-8"), 100000
    ).hex()

    return password_hash, salt


def verify_password(password: str, stored_hash: str) -> bool:
    """
    Verify a password against a stored hash.
    The stored_hash format is: salt$hash
    """
    try:
        parts = stored_hash.split("$")
        if len(parts) != 2:
            return False

        salt, expected_hash = parts
        computed_hash, _ = hash_password(password, salt)

        # Use constant-time comparison to prevent timing attacks
        return secrets.compare_digest(computed_hash, expected_hash)
    except Exception as e:
        logger.error(f"Error verifying password: {e}")
        return False


def create_password_hash(password: str) -> str:
    """
    Create a password hash string for storage.
    Returns: salt$hash
    """
    password_hash, salt = hash_password(password)
    return f"{salt}${password_hash}"


def validate_email(email: str) -> bool:
    """Validate email format."""
    pattern = r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
    return bool(re.match(pattern, email))


def validate_password(password: str) -> Tuple[bool, str]:
    """
    Validate password strength.
    Returns (is_valid, error_message).
    """
    if len(password) < 6:
        return False, "Password must be at least 6 characters long"
    if len(password) > 128:
        return False, "Password must be less than 128 characters"
    return True, ""


def validate_name(name: str) -> Tuple[bool, str]:
    """
    Validate user name.
    Returns (is_valid, error_message).
    """
    if not name or len(name.strip()) < 2:
        return False, "Name must be at least 2 characters long"
    if len(name) > 100:
        return False, "Name must be less than 100 characters"
    return True, ""
