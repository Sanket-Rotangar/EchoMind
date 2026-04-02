# Soora AI — Build & Deployment Summary

**Date:** April 2, 2026  
**Project:** Meeting Intelligence Platform (B2B SaaS)  
**Tagline:** AI Chief of Staff — record a meeting, get a structured executive brief automatically.

---

## What Was Built

Soora AI is a mobile-first meeting intelligence platform. Users record meetings on their Android phone. The system automatically transcribes the audio, extracts structured insights using AI, and presents a clean executive summary with decisions, action items, risks, and key metrics.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Mobile App | Flutter (Android) |
| Backend Platform | InsForge (Serverless Deno Edge Functions + PostgreSQL + Storage) |
| Transcription | AssemblyAI (speaker-labelled, universal-2 model) |
| Intelligence Extraction | Gemini 2.5 Flash (structured JSON schema output) |
| Scheduler | InsForge Cron (5-minute interval) |

---

## Architecture — The Pipeline

The system is a fully asynchronous, event-driven webhook pipeline. The user hits stop on their phone and walks away. Everything else happens in the cloud with no polling, no timeouts, and no user involvement.

### Data Flow

```
Flutter App
    │
    ├─► GET /storage-upload-url        → get pre-signed upload URL
    ├─► PUT (direct to storage bucket) → upload .m4a audio file
    └─► POST /audio-process            → register the meeting, kick the pipeline
                                              │
                                    ┌─────────▼─────────┐
                                    │   audio-worker     │
                                    │  stage: pending    │
                                    │  → transcribing    │
                                    └─────────┬──────────┘
                                              │ submits to AssemblyAI
                                              │ stores assembly_transcript_id
                                              ▼
                                       AssemblyAI Cloud
                                              │ (processes audio async)
                                              │ POSTs back when done
                                              ▼
                                    ┌─────────────────────┐
                                    │  assembly-webhook   │
                                    │  stage: transcribing│
                                    │  → transcribed      │
                                    │  saves raw_transcript│
                                    └─────────┬───────────┘
                                              │ fire-and-forget
                                              ▼
                                    ┌─────────────────────┐
                                    │ extract-intelligence│
                                    │ stage: transcribed  │
                                    │ → extracting        │
                                    │ calls Gemini 2.5    │
                                    │ → completed (RPC)   │
                                    └─────────────────────┘
```

### Pipeline Stages (DB State Machine)

Every meeting row in the database drives the pipeline through these stages:

```
pending → transcribing → transcribed → extracting → completed
                                                  ↘ failed
```

Each stage transition is atomic — only one function invocation can claim a stage at a time. This prevents duplicate processing even if functions are called multiple times.

---

## Edge Functions (8 Total)

| Function | Role |
|---|---|
| `storage-upload-url` | Returns a pre-signed URL for Flutter to upload audio directly to storage |
| `audio-process` | Creates the meeting record, kicks audio-worker fire-and-forget, returns 202 immediately |
| `audio-worker` | Gets download URL, submits audio to AssemblyAI, stores transcript ID, claims `transcribing` stage atomically |
| `assembly-webhook` | Receives AssemblyAI callback, saves raw transcript, hands off to extract-intelligence |
| `extract-intelligence` | Reads raw transcript, calls Gemini 2.5 Flash, commits all results atomically via RPC |
| `audio-worker-cron` | Cleanup job — retries genuinely stuck meetings by stage bucket |
| `meetings-list` | Returns paginated meeting list for Flutter home screen |
| `meeting-detail` | Returns full meeting detail including intelligence_data and action_items |

---

## Database Schema

### `meetings` table (15 columns)

| Column | Type | Purpose |
|---|---|---|
| id | UUID | Primary key |
| user_id | UUID | Owner |
| title | TEXT | Auto-generated from bottom_line |
| status | TEXT | processing / completed / failed |
| stage | TEXT | Pipeline stage (state machine driver) |
| audio_storage_path | TEXT | Path in storage bucket |
| assembly_transcript_id | TEXT | Idempotency key — set once, never re-submitted |
| raw_transcript | JSONB | Speaker-labelled transcript array — Gemini reads this |
| intelligence_data | JSONB | Full Gemini output |
| retry_count | INTEGER | Per-meeting retry counter |
| last_error | TEXT | Last failure message for debugging |
| last_attempted_at | TIMESTAMPTZ | Used by cron to detect stale meetings |
| attempts | INTEGER | Legacy column (kept for compatibility) |
| created_at | TIMESTAMPTZ | |
| updated_at | TIMESTAMPTZ | Auto-updated by trigger |

**Constraint:** `UNIQUE (user_id, audio_storage_path)` — prevents duplicate meetings if Flutter retries the upload.

### `action_items` table

| Column | Type |
|---|---|
| id | UUID |
| meeting_id | UUID (FK → meetings, CASCADE DELETE) |
| assignee | TEXT |
| task_description | TEXT |
| deadline | TEXT (nullable) |
| created_at / updated_at | TIMESTAMPTZ |

### Postgres Function

`commit_meeting_results(p_meeting_id, p_insights, p_title)` — atomic transaction that updates the meeting row, deletes old action items, and inserts new action items in a single database transaction. Called via RPC from extract-intelligence. Eliminates the data loss window that existed in the previous design.

---

## AI Output Schema (Gemini Structured Output)

Gemini 2.5 Flash is constrained to return exactly this JSON structure:

```json
{
  "bottom_line": "One-sentence core objective of the meeting",
  "decisions_register": ["Decision 1", "Decision 2"],
  "action_matrix": [
    { "assignee": "Speaker A", "task": "Task description", "deadline": "2026-04-10" }
  ],
  "risks_and_blockers": ["Risk 1", "Blocker 2"],
  "key_metrics": ["Metric 1", "Metric 2"]
}
```

---

## Reliability Design

### What makes it resilient

**Atomic stage claims** — every stage transition uses a conditional DB update (`WHERE stage = 'current_stage'`). If two function invocations race, only one proceeds. The other exits cleanly.

**Idempotency keys** — `assembly_transcript_id` is stored immediately after AssemblyAI submission. If audio-worker is called again, it sees the ID already exists and exits without re-submitting. AssemblyAI credits are never burned twice.

**Raw transcript persistence** — the transcript is saved to the DB before Gemini is called. If Gemini fails, the cron retries only the Gemini step. AssemblyAI is never called again for that meeting.

**Atomic commit** — all three DB writes (update meeting, delete old action items, insert new action items) happen inside a single Postgres transaction via RPC. No partial states.

**Webhook secret in header** — `WEBHOOK_SECRET` is passed via `x-webhook-token` header, not in the URL. It no longer appears in logs or CDN access records.

**Duplicate upload protection** — unique constraint on `(user_id, audio_storage_path)` means Flutter retries return the existing meetingId instead of creating ghost rows.

### Cron — 3 Retry Buckets (runs every 5 minutes)

| Bucket | Targets | Action |
|---|---|---|
| 1 | `pending` or `transcribing` with no `assembly_transcript_id` | Re-kicks audio-worker (re-submits to AssemblyAI) |
| 2 | `transcribed` with `raw_transcript` present | Re-kicks extract-intelligence only (Gemini retry, no AssemblyAI) |
| 3 | Any stuck stage with `retry_count >= 3` | Marks as `failed` |

Double-retry prevention: optimistic locking on `retry_count` — the cron only updates a row if `retry_count` matches what it read. Concurrent cron runs skip rows already claimed.

---

## Security

| Concern | Solution |
|---|---|
| Webhook auth | Secret in `x-webhook-token` header, not URL |
| Storage access | Private bucket, pre-signed URLs with 1hr expiry |
| Function auth | `API_KEY` (admin) used for internal function-to-function calls |
| Secrets management | All keys stored in InsForge secrets, never hardcoded |

---

## Deployed Infrastructure

**Project:** My First Project  
**Region:** ap-southeast  
**Host:** `https://nm5x7yfa.ap-southeast.insforge.app`  
**Functions URL:** `https://nm5x7yfa.functions.insforge.app`

**Active Secrets:** `INSFORGE_BASE_URL`, `API_KEY`, `ASSEMBLYAI_API_KEY`, `GEMINI_API_KEY`, `WEBHOOK_SECRET`, `WEBHOOK_PUBLIC_BASE_URL`, `ANON_KEY`, `DUMMY_USER_ID`

**Cron Schedule:** Every 5 minutes (`*/5 * * * *`) → POST `/functions/audio-worker-cron`

---

## How to Debug a Stuck Meeting

```bash
# Check what stage a meeting is stuck at and why
npx @insforge/cli db query "SELECT id, stage, status, retry_count, last_error, assembly_transcript_id IS NOT NULL as has_transcript FROM meetings ORDER BY created_at DESC LIMIT 5"

# Watch function execution logs
npx @insforge/cli logs function.logs

# Full backend health check
npx @insforge/cli diagnose
```

---

## How to Run the Flutter App

```bash
cd meeting_app
flutter run
```

For Android specifically:
```bash
flutter run -d android
```