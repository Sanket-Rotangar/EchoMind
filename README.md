# MeetingApp — Flutter + FastAPI + Supabase

This workspace runs on:
- Flutter app (`meeting_app`)
- FastAPI backend (`meeting_backend`)
- Supabase (Postgres + Storage)
- AssemblyAI (transcription)
- Gemini (meeting intelligence extraction)

## Pipeline State Model

Meetings move through these persisted statuses:
- `uploaded`
- `transcribing`
- `transcribed`
- `analyzing`
- `completed`
- `failed`

Each transition is stored in `meeting_state_events` for debugging and retry visibility.

## End-to-End Flow

1. Flutter records audio.
2. Flutter requests upload URL: `GET /api/v1/storage/upload-url`.
3. Flutter uploads audio directly to Supabase Storage.
4. Flutter starts processing: `POST /api/meetings/process`.
5. Backend inserts meeting (`uploaded`) and submits to AssemblyAI (`transcribing`).
6. Backend receives AssemblyAI webhook, or falls back to transcript polling if webhook cannot reach backend.
7. Backend stores transcript (`transcribed`), runs Gemini (`analyzing`), and writes insights/action items (`completed`).
8. Flutter fetches list/details:
   - `GET /api/v1/meetings`
   - `GET /api/v1/meetings/{id}`

## Environment

Create `.env` at workspace root:

```env
SUPABASE_URL=...
SUPABASE_SERVICE_ROLE_KEY=...
SUPABASE_BUCKET=meetings
ASSEMBLYAI_API_KEY=...
GEMINI_API_KEY=...
WEBHOOK_SECRET=...
WEBHOOK_PUBLIC_BASE_URL=http://localhost:8000
```

## Database Migrations (Supabase SQL Editor)

Run in order:
1. `meeting_backend/migrations/001_supabase_core.sql`
2. `meeting_backend/migrations/003_pipeline_stage_states.sql`
3. `meeting_backend/migrations/004_meeting_status_enum_compat.sql`

Migration `004` handles legacy enum-based `meetings.status` setups safely.

## Run Backend

cd meeting_backend && /home/sanket-rotangar/.local/bin/python3.9 -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload

## Run Flutter

cd meeting_app && flutter run -d 113f5562 --dart-define=FASTAPI_BASE_URL=http://10.17.197.126:8000


## Backend Tests

```bash
cd meeting_backend
/home/sanket-rotangar/Desktop/MeetingApp/.venv/bin/python -m unittest test_api_e2e.py test_pipeline_services.py
```

## Quick Curl Smoke Test

```bash
cd meeting_backend
USER_ID=<valid-users.id-uuid> ./test_pipeline_with_curl.sh /home/sanket-rotangar/Desktop/MeetingApp/test-audio.m4a
```
