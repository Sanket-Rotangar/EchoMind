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
- `meeting_backend/assembly_service.py` — submit transcript jobs to AssemblyAI + polling fallback
- `meeting_backend/ai_service.py` — fetch transcript + Gemini extraction + idempotent DB updates

### 3) Supabase Data Model

Migration:
- `meeting_backend/migrations/001_supabase_core.sql`
- `meeting_backend/migrations/003_pipeline_stage_states.sql`
- `meeting_backend/migrations/004_meeting_status_enum_compat.sql`

Tables:
- `meetings`
  - lifecycle status: `uploaded`, `transcribing`, `transcribed`, `analyzing`, `completed`, `failed`
  - stores transcript linkage (`assembly_transcript_id`), full `transcript_text`, final `intelligence_data`, and `failure_reason`
- `action_items`
  - normalized task rows extracted from Gemini output
- `meeting_state_events`
  - append-only stage audit trail with JSON `details` per transition for debugging and retry visibility

Notes:
- Stage transitions are persisted by backend services using `db_client.transition_meeting_state(...)`.
- This keeps the pipeline observable and makes later retry orchestration straightforward.

## Sequence Flow

1. Flutter records audio.
2. Flutter calls `GET /api/v1/storage/upload-url`.
3. FastAPI creates object path and requests Supabase signed upload URL.
4. Flutter uploads bytes directly to Supabase Storage signed URL.
5. Flutter calls `POST /api/meetings/process` with `{ path }`.
6. FastAPI inserts `meetings` row with state `uploaded` and starts background submission to AssemblyAI.
7. After AssemblyAI accepts the job, backend sets state `transcribing` and stores `assembly_transcript_id`.
8. AssemblyAI calls `POST /api/webhooks/assemblyai` after transcription.
9. If webhook is unreachable, backend polls AssemblyAI transcript status as fallback.
10. Backend fetches transcript, stores `transcript_text`, and sets state `transcribed`.
11. Backend sends transcript to Gemini and sets state `analyzing`.
12. Backend stores insights and action items, then sets state `completed`.
13. Flutter polls/refreshes list and opens detail view.

## Error Handling (MVP)

- Missing user header (`x-user-id`) returns `400`.
- Invalid webhook secret returns `401`.
- Any transcription/extraction failure marks meeting `failed` and stores `failure_reason`.
- Every stage transition is recorded in `meeting_state_events` for debugging.
- Duplicate completion callbacks are handled safely (idempotent terminal-state guard).
- Retry queue/worker is still not implemented yet, but state/event data is now in place to support it.

## Validation

Verified by backend tests:
- `meeting_backend/test_api_e2e.py`
- `meeting_backend/test_pipeline_services.py`
