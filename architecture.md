# Architecture — MeetingApp (Current)

## Stack

- **Frontend:** Flutter (`meeting_app`)
- **Backend API:** FastAPI (`meeting_backend/main.py`)
- **Database:** Supabase Postgres (`meetings`, `action_items`)
- **File Storage:** Supabase Storage bucket (`meetings`)
- **Transcription:** AssemblyAI
- **Intelligence Extraction:** Gemini

No legacy third-party backend platform services are used in the active runtime path.

## Components

### 1) Flutter Client

Key integration file:
- `meeting_app/lib/core/api_service.dart`

Responsibilities:
- Request signed upload URL from FastAPI
- Upload recorded audio directly to Supabase Storage
- Trigger background processing
- Fetch meetings list and meeting details

### 2) FastAPI Backend

Entry point:
- `meeting_backend/main.py`

Endpoints:
- `GET /health`
- `GET /api/v1/storage/upload-url`
- `POST /api/meetings/process`
- `POST /api/webhooks/assemblyai`
- `GET /api/v1/meetings`
- `GET /api/v1/meetings/{meeting_id}`

Services:
- `meeting_backend/db_client.py` — Supabase DB + Storage interactions
- `meeting_backend/assembly_service.py` — submit transcript jobs to AssemblyAI
- `meeting_backend/ai_service.py` — fetch transcript + Gemini extraction + DB updates

### 3) Supabase Data Model

Migration:
- `meeting_backend/migrations/001_supabase_core.sql`

Tables:
- `meetings`
  - lifecycle status: `processing`, `completed`, `failed`
  - stores transcript linkage (`assembly_transcript_id`) and final `intelligence_data`
- `action_items`
  - normalized task rows extracted from Gemini output

Excluded intentionally (for now): retry/attempt columns and stage state-machine complexity.

## Sequence Flow

1. Flutter records audio.
2. Flutter calls `GET /api/v1/storage/upload-url`.
3. FastAPI creates object path and requests Supabase signed upload URL.
4. Flutter uploads bytes directly to Supabase Storage signed URL.
5. Flutter calls `POST /api/meetings/process` with `{ path }`.
6. FastAPI inserts `meetings` row (`processing`) and starts background submission to AssemblyAI.
7. AssemblyAI calls `POST /api/webhooks/assemblyai` after transcription.
8. FastAPI fetches transcript from AssemblyAI and builds speaker text.
9. FastAPI sends prompt to Gemini and parses strict JSON response.
10. FastAPI updates `meetings` to `completed`, saves `intelligence_data`, and replaces `action_items`.
11. Flutter polls/refreshes list and opens detail view.

## Error Handling (MVP)

- Missing user header (`x-user-id`) returns `400`.
- Invalid webhook secret returns `401`.
- Any transcription/extraction failure marks meeting `failed`.
- No retry queue is included yet by design.

## Validation

Verified by backend tests:
- `meeting_backend/test_api_e2e.py`
- `meeting_backend/test_pipeline_services.py`
