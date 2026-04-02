# InsForge Deployment & Connectivity Analysis

Date: 2026-04-01
Project: `My First Project` (`f499c96d-49b3-49c2-acfb-1f855fd69ada`)
Region: `ap-southeast`
Host: `https://nm5x7yfa.ap-southeast.insforge.app`

## 1) What is deployed on InsForge right now

## Active Edge Functions
- `storage-upload-url`
- `audio-process`
- `audio-worker`
- `meetings-list`
- `meeting-detail`

## Active Scheduler
- `audio-worker-cron` (`*/2 * * * *`)
- Calls: `POST /functions/audio-worker`

## Storage
- Bucket: `meetings` (private)

## Database
- Tables: `meetings`, `action_items`
- RLS policies: present on both tables
- Triggers: `updated_at` auto-update triggers

## Frontend Integration
- Frontend now points to InsForge function endpoints in [meeting_app/lib/core/api_service.dart](meeting_app/lib/core/api_service.dart).
- Endpoint mapping documented in [insforge/function-endpoint-map.md](insforge/function-endpoint-map.md).

---

## 2) How services are connected (runtime architecture)

## Request/Processing Flow
1. Flutter app calls `GET /functions/storage-upload-url`.
2. Function asks InsForge Storage API for upload strategy.
3. Flutter uploads audio to storage using returned strategy (`presigned` or `direct`).
4. Flutter confirms upload when `confirmRequired=true`.
5. Flutter calls `POST /functions/audio-process` with `path`.
6. `audio-process` inserts placeholder row in `meetings` (`status=processing`) and returns immediately.
7. `audio-process` triggers `audio-worker` asynchronously.
8. `audio-worker` fetches audio download strategy from InsForge storage.
9. `audio-worker` calls external AI services:
   - AssemblyAI for transcription
   - Gemini for structured insights extraction
10. `audio-worker` updates `meetings` and inserts `action_items`.
11. Frontend fetches lists/details from:
   - `GET /functions/meetings-list`
   - `GET /functions/meeting-detail?id=<meetingId>`

## Reliability Path
- Cron (`audio-worker-cron`) invokes `audio-worker` every 2 minutes.
- This helps process items that remain in `processing` if immediate fire-and-forget invocation fails.

## Observability
- Function logs available via `npx @insforge/cli logs function.logs`.
- Health checks via `npx @insforge/cli diagnose`.

---

## 3) External dependencies still used

Even with backend hosted on InsForge, these external APIs are still part of processing:
- AssemblyAI (`ASSEMBLYAI_API_KEY`)
- Gemini (`GEMINI_API_KEY`)

So architecture is:
- **Platform services**: InsForge (functions, db, storage, scheduler, logs)
- **AI providers**: AssemblyAI + Gemini

---

## 4) Supabase links — should you remove them?

Short answer: **Yes — completed. Supabase links were removed from active configuration**, because active runtime no longer uses Supabase services.

## Why this is safe now
- Active function code uses InsForge DB/Storage APIs.
- Frontend code uses InsForge functions.
- Supabase references are only in:
  - archived legacy code under [temp/legacy-backend](temp/legacy-backend)
  - historical docs/plans such as [analysis.md](analysis.md)

## Cleanup status (completed)
- Deleted InsForge secrets:
  - `SUPABASE_URL`
  - `SUPABASE_ANON_KEY`
  - `SUPABASE_SERVICE_ROLE_KEY`
- Removed local `.env` Supabase variables.
- Removed root dependency `@supabase/supabase-js`.

## Remaining optional cleanup
1. If you will never rollback to legacy code, remove Supabase references from archived files under `temp/legacy-backend`.
2. Keep historical migration docs (`analysis.md`) as legacy context, or add explicit "pre-InsForge" labeling.

---

## 5) Risk notes before deleting Supabase secrets

- If you plan to run anything under [temp/legacy-backend](temp/legacy-backend), keep Supabase secrets.
- If all traffic is fully cut over to InsForge functions and legacy rollback is not required, remove them.

---

## 6) Current conclusion

Deployment and connectivity are now centered on InsForge for backend runtime.
Supabase links are now **legacy artifacts only in archived/history files**, not runtime requirements for the active path.
