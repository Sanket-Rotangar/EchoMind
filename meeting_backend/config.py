import os
import json
from dotenv import load_dotenv

env_path = os.path.join(os.path.dirname(__file__), "..", ".env")
load_dotenv(env_path)


def _csv_env(name: str, default: str = "") -> list[str]:
    raw = os.getenv(name, default)
    return [item.strip() for item in raw.split(",") if item.strip()]


APP_ENV = os.getenv("APP_ENV", "").strip().lower() or (
    "production" if os.getenv("RENDER") else "development"
)
IS_PRODUCTION = APP_ENV == "production"

BACKEND_PORT = int(os.getenv("BACKEND_PORT", os.getenv("PORT", "8000")))

SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_SERVICE_ROLE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "")
SUPABASE_BUCKET = os.getenv("SUPABASE_BUCKET", "meetings")
ASSEMBLYAI_API_KEY = os.getenv("ASSEMBLYAI_API_KEY", "")
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")
WEBHOOK_SECRET = os.getenv("WEBHOOK_SECRET", "")

_render_external_url = os.getenv("RENDER_EXTERNAL_URL", "").strip().rstrip("/")
_webhook_base_url = os.getenv("WEBHOOK_PUBLIC_BASE_URL", "").strip()
if not _webhook_base_url and _render_external_url:
    _webhook_base_url = _render_external_url
if not _webhook_base_url:
    _webhook_base_url = f"http://localhost:{BACKEND_PORT}"
WEBHOOK_PUBLIC_BASE_URL = _webhook_base_url.rstrip("/")

# Local network configuration - UPDATE LOCAL_IP in .env when you change WiFi
LOCAL_IP = os.getenv("LOCAL_IP", "").strip()
LOCAL_BACKEND_URL = (
    f"http://{LOCAL_IP}:{BACKEND_PORT}"
    if LOCAL_IP
    else f"http://localhost:{BACKEND_PORT}"
)

# CORS (comma-separated env values; defaults are permissive only in development)
CORS_ALLOW_ORIGINS = _csv_env(
    "CORS_ALLOW_ORIGINS", "*" if not IS_PRODUCTION else ""
)
if not CORS_ALLOW_ORIGINS:
    CORS_ALLOW_ORIGINS = ["*"] if not IS_PRODUCTION else []
CORS_ALLOW_METHODS = _csv_env("CORS_ALLOW_METHODS", "*") or ["*"]
CORS_ALLOW_HEADERS = _csv_env("CORS_ALLOW_HEADERS", "*") or ["*"]
CORS_ALLOW_CREDENTIALS = (
    os.getenv("CORS_ALLOW_CREDENTIALS", "false").strip().lower() == "true"
)
if "*" in CORS_ALLOW_ORIGINS and CORS_ALLOW_CREDENTIALS:
    # Browsers ignore wildcard origins when credentials are enabled.
    CORS_ALLOW_CREDENTIALS = False

# Google OAuth - Web Client (for backend auth and calendar)
GOOGLE_CLIENT_ID = os.getenv("GOOGLE_CLIENT_ID", "")
GOOGLE_CLIENT_SECRET = os.getenv("GOOGLE_CLIENT_SECRET", "")
# Default redirect URI - the app can override this with loopback URIs
# Google allows http://127.0.0.1:port for loopback OAuth
GOOGLE_REDIRECT_URI = os.getenv("GOOGLE_REDIRECT_URI", "").strip()
if not GOOGLE_REDIRECT_URI:
    if IS_PRODUCTION and WEBHOOK_PUBLIC_BASE_URL.startswith("https://"):
        GOOGLE_REDIRECT_URI = (
            f"{WEBHOOK_PUBLIC_BASE_URL}/auth/google/calendar/callback"
        )
    else:
        GOOGLE_REDIRECT_URI = "http://127.0.0.1:8085/callback"

GOOGLE_FALLBACK_REDIRECT_URIS = _csv_env("GOOGLE_FALLBACK_REDIRECT_URIS", "")
if not GOOGLE_FALLBACK_REDIRECT_URIS and not IS_PRODUCTION:
    GOOGLE_FALLBACK_REDIRECT_URIS = [
        "http://localhost:8000/auth/google/callback",
        "http://127.0.0.1:8000/auth/google/callback",
    ]

ALLOW_LOCAL_GOOGLE_SECRET_FILES = (
    os.getenv(
        "ALLOW_LOCAL_GOOGLE_SECRET_FILES", "false" if IS_PRODUCTION else "true"
    )
    .strip()
    .lower()
    == "true"
)

# Android Client ID (for verifying mobile sign-in tokens)
GOOGLE_ANDROID_CLIENT_ID = os.getenv("GOOGLE_ANDROID_CLIENT_ID", "")


# Load from JSON file if env vars not set
def _load_google_credentials():
    global \
        GOOGLE_CLIENT_ID, \
        GOOGLE_CLIENT_SECRET, \
        GOOGLE_REDIRECT_URI, \
        GOOGLE_ANDROID_CLIENT_ID

    base_dir = os.path.dirname(__file__)

    # Load Web client credentials (for calendar OAuth)
    if not (GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET):
        web_secret_file = os.path.join(
            base_dir,
            "client_secret_892230117968-s3n9bugmvj04n8dfb9056vc0gc2ve0p3.apps.googleusercontent.com.json",
        )
        if os.path.exists(web_secret_file):
            with open(web_secret_file, "r") as f:
                data = json.load(f)
                web_config = data.get("web", {})
                if web_config:
                    GOOGLE_CLIENT_ID = web_config.get("client_id", GOOGLE_CLIENT_ID)
                    GOOGLE_CLIENT_SECRET = web_config.get(
                        "client_secret", GOOGLE_CLIENT_SECRET
                    )
                    # Note: We don't override GOOGLE_REDIRECT_URI from JSON
                    # because we use loopback redirect (http://127.0.0.1:port)
                    # for mobile app OAuth flow

    # Load Android client ID (for verifying mobile app sign-in)
    if not GOOGLE_ANDROID_CLIENT_ID:
        android_secret_file = os.path.join(
            base_dir,
            "client_secret_892230117968-74e5uakr8aim84e6ukl7r5aloibv2g9b.apps.googleusercontent.com.json",
        )
        if os.path.exists(android_secret_file):
            with open(android_secret_file, "r") as f:
                data = json.load(f)
                installed_config = data.get("installed", {})
                if installed_config:
                    GOOGLE_ANDROID_CLIENT_ID = installed_config.get("client_id", "")

if ALLOW_LOCAL_GOOGLE_SECRET_FILES:
    _load_google_credentials()

# JWT Secret for signing tokens
DEFAULT_JWT_SECRET = "echomind-secret-key-change-in-production-2024"
JWT_SECRET = os.getenv("JWT_SECRET", DEFAULT_JWT_SECRET)
JWT_ALGORITHM = "HS256"
JWT_EXPIRY_HOURS = 24 * 7  # 1 week

# Validation
REQUIRED_VARS = [
    ("SUPABASE_URL", SUPABASE_URL),
    ("SUPABASE_SERVICE_ROLE_KEY", SUPABASE_SERVICE_ROLE_KEY),
    ("ASSEMBLYAI_API_KEY", ASSEMBLYAI_API_KEY),
    ("GEMINI_API_KEY", GEMINI_API_KEY),
    ("WEBHOOK_SECRET", WEBHOOK_SECRET),
]


def validate_config():
    missing = [name for name, val in REQUIRED_VARS if not val]
    if missing:
        raise ValueError(
            f"Missing required environment variables: {', '.join(missing)}"
        )

    if IS_PRODUCTION:
        if JWT_SECRET == DEFAULT_JWT_SECRET:
            raise ValueError("JWT_SECRET must be set to a strong value in production")

        if (
            "localhost" in WEBHOOK_PUBLIC_BASE_URL
            or "127.0.0.1" in WEBHOOK_PUBLIC_BASE_URL
            or not WEBHOOK_PUBLIC_BASE_URL
        ):
            raise ValueError(
                "WEBHOOK_PUBLIC_BASE_URL must be a public HTTPS URL in production"
            )
