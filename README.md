# MeetingApp — Supabase + FastAPI Pipeline

This workspace now runs on:
- Flutter app (`meeting_app`)
- FastAPI backend (`meeting_backend`)
- Supabase (Postgres + Storage)
- AssemblyAI (transcription)
- Gemini (structured meeting intelligence)

Legacy function/runtime dependencies were removed from active code paths.

## End-to-End Flow

1. Flutter records audio.
2. Flutter requests upload URL from FastAPI: `GET /api/v1/storage/upload-url`.
3. Flutter uploads audio directly to Supabase Storage using the signed URL.
4. Flutter starts processing: `POST /api/meetings/process` with storage `path`.
5. FastAPI creates a meeting row (`processing`) and submits audio to AssemblyAI.
6. AssemblyAI calls webhook: `POST /api/webhooks/assemblyai`.
7. FastAPI fetches transcript, sends it to Gemini, writes summary + action items to Supabase.
8. Flutter reads list/details from FastAPI:
   - `GET /api/v1/meetings`
   - `GET /api/v1/meetings/{id}`

## Backend Setup

Create `.env` at workspace root with:

```env
SUPABASE_URL=...
SUPABASE_SERVICE_ROLE_KEY=...
SUPABASE_BUCKET=meetings
ASSEMBLYAI_API_KEY=...
GEMINI_API_KEY=...
WEBHOOK_SECRET=...
WEBHOOK_PUBLIC_BASE_URL=http://localhost:8000
```

Apply schema in Supabase SQL editor (or migration tooling):
- `meeting_backend/migrations/001_supabase_core.sql`

## Run Backend

```bash
cd meeting_backend
/home/sanket-rotangar/Desktop/MeetingApp/.venv/bin/python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

## Run Flutter App

```bash
cd meeting_app
flutter run \
  --dart-define=FASTAPI_BASE_URL=http://<your-ip>:8000 \
  --dart-define=SOORA_USER_ID=<uuid-or-user-id>
```

## Tests

```bash
cd meeting_backend
/home/sanket-rotangar/Desktop/MeetingApp/.venv/bin/python -m unittest test_api_e2e.py test_pipeline_services.py
```

Current status: tests pass for migrated backend APIs and pipeline services.
