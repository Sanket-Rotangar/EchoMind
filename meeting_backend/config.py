import os
from dotenv import load_dotenv

env_path = os.path.join(os.path.dirname(__file__), '..', '.env')
load_dotenv(env_path)

SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_SERVICE_ROLE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "")
SUPABASE_BUCKET = os.getenv("SUPABASE_BUCKET", "meetings")
ASSEMBLYAI_API_KEY = os.getenv("ASSEMBLYAI_API_KEY", "")
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")
WEBHOOK_SECRET = os.getenv("WEBHOOK_SECRET", "")
WEBHOOK_PUBLIC_BASE_URL = os.getenv("WEBHOOK_PUBLIC_BASE_URL", "http://localhost:8000")

# Validation
REQUIRED_VARS = [
    ("SUPABASE_URL", SUPABASE_URL),
    ("SUPABASE_SERVICE_ROLE_KEY", SUPABASE_SERVICE_ROLE_KEY),
    ("ASSEMBLYAI_API_KEY", ASSEMBLYAI_API_KEY),
    ("GEMINI_API_KEY", GEMINI_API_KEY),
    ("WEBHOOK_SECRET", WEBHOOK_SECRET)
]

def validate_config():
    missing = [name for name, val in REQUIRED_VARS if not val]
    if missing:
        raise ValueError(f"Missing required environment variables: {', '.join(missing)}")

