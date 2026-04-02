# InsForge Backend Migration Plan

## Goal
Migrate the current Node/Express backend to InsForge-managed backend services, while preserving existing behavior and APIs for the frontend.

## Non-Negotiable Rules
1. Do **not** delete legacy backend code.
2. Move legacy backend files to a temp archive folder **only after** the equivalent InsForge piece is migrated and verified.
3. Migrate in small, testable increments.
4. Keep frontend contract (`/api/v1/...`) stable unless intentionally versioned.

---

## Current Status (as of 2026-04-01)
- InsForge project linked successfully:
  - Project ID: `f499c96d-49b3-49c2-acfb-1f855fd69ada`
  - App Key: `nm5x7yfa`
  - Region: `ap-southeast`
- InsForge CLI available (`@insforge/cli 0.1.36`).
- InsForge agent skills installed during `insforge link`.
- Existing backend analyzed in `analysis.md`.
- Phase 0 baseline artifact created in `phase0-baseline.md`.

---

## Phase Plan

## Phase 0 — Baseline & Mapping
**Objective:** Freeze current behavior to avoid regression.

Tasks:
- [x] Record all existing API request/response contracts from `analysis.md`.
- [x] Define migration parity checklist per endpoint:
  - [x] `GET /api/v1/storage/upload-url`
  - [x] `POST /api/v1/audio/process`
  - [x] `GET /api/v1/meetings`
  - [x] `GET /api/v1/meetings/:id`
  - [x] (Optional legacy) `POST /api/v1/audio/upload`
- [x] Decide whether local multipart upload endpoint is kept or retired.

Success Gate:
- [x] Endpoint parity checklist documented.
- [ ] Endpoint parity checklist agreed.

Deliverable:
- `phase0-baseline.md` (canonical contract + parity matrix + endpoint decision)

---

## Phase 1 — InsForge Project Scaffolding
**Objective:** Prepare InsForge resources used by migrated backend.

Tasks:
- [x] Inspect existing cloud resources:
  - [x] `npx @insforge/cli metadata`
  - [x] `npx @insforge/cli db tables`
  - [x] `npx @insforge/cli storage buckets`
- [x] Create required storage bucket(s) if missing (likely `meetings`).
- [x] Configure all required secrets:
  - [x] `ASSEMBLYAI_API_KEY`
  - [x] `GEMINI_API_KEY`
  - [x] `DUMMY_USER_ID`
  - [x] `SUPABASE_URL`
  - [x] `SUPABASE_ANON_KEY`
  - [x] `SUPABASE_SERVICE_ROLE_KEY`
- [x] Run health check: `npx @insforge/cli diagnose`

Success Gate:
- [x] DB tables and bucket availability confirmed.
- [x] Secrets present.
- [x] Diagnose passes without blockers.

---

## Phase 2 — Database Schema & Policies
**Objective:** Ensure InsForge DB supports current data model safely.

Tasks:
- [x] Validate/create tables and relations:
  - [x] `meetings`
  - [x] `action_items`
- [x] Add/verify indexes for list/detail queries.
- [x] Define RLS policies for per-user data isolation.
- [x] Add SQL migration files under a new folder: `insforge/migrations/`.
- [x] Apply migrations via CLI (`db import` or `db query` sequence).

Success Gate:
- [x] Schema + relations + indexes in place.
- [ ] RLS policies enforced and tested in authenticated runtime flow.

---

## Phase 3 — Replace Express Routes with InsForge Functions
**Objective:** Move route logic into InsForge edge functions.

Function-by-function migration order:
1. [x] Storage signed upload URL function
2. [x] Meetings list function
3. [x] Meeting detail function
4. [x] Audio process trigger function (202 + async pattern)
5. [x] Async processing worker strategy (scheduled/queued function)

Per-function checklist (apply to each):
- [ ] Implement function code.
- [ ] Deploy with `npx @insforge/cli functions deploy <slug>`.
- [ ] Invoke test with `npx @insforge/cli functions invoke <slug>`.
- [ ] Verify response parity with existing Express endpoint.
- [ ] Update integration mapping for frontend base URL if needed.

Success Gate:
- [x] All required API behaviors available through InsForge functions.

---

## Phase 4 — Async Pipeline Reliability
**Objective:** Recreate background AI pipeline in durable InsForge-native way.

Tasks:
- [x] Implement background pipeline trigger and worker split.
- [x] Add retry/error handling and failure state updates (`status = failed`).
- [x] Ensure idempotency for repeated processing triggers.
- [x] Add logging strategy and verify via `insforge logs`.

Success Gate:
- [x] End-to-end: upload path -> processing -> insights + action items persisted.
- [x] Failure path updates status correctly and logs are observable.

---

## Phase 5 — Legacy Backend Archival (Incremental)
**Objective:** Move Express code to temp archive only after parity passes.

Archive policy:
- Temp archive folder: `temp/legacy-backend/`

Incremental move sequence:
- [x] After storage endpoint parity: move `routes/storageRoutes.js`, `controllers/storageController.js`
- [x] After meetings parity: move `routes/meetingRoutes.js`, `controllers/meetingController.js`
- [x] After audio parity: move `routes/audioRoutes.js`, `controllers/audioController.js`
- [x] After service parity: move legacy `services/*.js` not needed by InsForge runtime
- [x] Final move: `server.js` moved to temp archive after successful InsForge endpoint parity and E2E tests

Success Gate:
- [x] Legacy backend fully archived under temp path.
- [x] No active dependency on Express server runtime.

---

## Phase 6 — Validation, Cutover & Hardening
**Objective:** Production-ready migration completion.

Tasks:
- [ ] Run full API regression tests (manual + scripted).
- [ ] Verify frontend works with InsForge backend endpoints.
- [ ] Remove dummy user usage and bind user identity to real auth context.
- [ ] Document operational runbook (deploy, rollback, logs, secrets rotation).
- [ ] Final migration report update in `analysis.md` or `migration-report.md`.

Success Gate:
- [ ] Frontend stable on InsForge.
- [ ] Rollback path documented.
- [ ] Team handoff docs complete.

---

## Working Log (Update on each migration task)

### Entry Template
- Date:
- Phase:
- Task:
- Command(s) Run:
- Result:
- Verification:
- Legacy Files Moved:
- Next Step:

### Log Entries
- 2026-04-01: Initialized migration plan and linked project.
- 2026-04-01: Completed Phase 0 baseline mapping and parity matrix in `phase0-baseline.md`.
  - Decision: `POST /api/v1/audio/upload` marked as optional legacy endpoint and planned for retirement post parity validation.
  - Next required check: stakeholder sign-off, then begin Phase 1 resource inspection.
- 2026-04-01: Completed Phase 1 InsForge scaffolding.
  - Commands run:
    - `npx @insforge/cli metadata --json`
    - `npx @insforge/cli db tables`
    - `npx @insforge/cli storage buckets`
    - `npx @insforge/cli storage create-bucket meetings --private -y`
    - `npx @insforge/cli secrets list --all`
    - `npx @insforge/cli secrets add/update ...` (upserted from `.env`)
    - `npx @insforge/cli diagnose`
  - Results:
    - Blank project confirmed (no tables/functions initially).
    - `meetings` private bucket created.
    - Required backend secrets added.
    - Health report returned without critical blockers.
  - Next required step: Phase 2 schema + indexes + RLS migration.
- 2026-04-01: Executed Phase 2 schema migration.
  - Migration file: `insforge/migrations/001_meetings_action_items.sql`
  - Commands run:
    - `npx @insforge/cli db import insforge/migrations/001_meetings_action_items.sql`
    - `npx @insforge/cli db tables`
    - `npx @insforge/cli db indexes`
    - `npx @insforge/cli db policies`
    - `npx @insforge/cli db triggers`
  - Results:
    - Tables created: `meetings`, `action_items` with FK `action_items.meeting_id -> meetings.id`.
    - Indexes created: `idx_meetings_user_created_at`, `idx_meetings_status`, `idx_action_items_meeting_id`.
    - RLS policies created for authenticated users on both tables.
    - `updated_at` trigger function and table triggers created.
  - Pending validation:
    - Full authenticated runtime RLS behavior will be validated during function invocation tests in Phase 3.
  - Next required step: begin Phase 3 with `GET /api/v1/storage/upload-url` function migration.
- 2026-04-01: Completed Phase 3 slice for storage upload URL endpoint.
  - Function source created: `insforge/functions/storage-upload-url/index.ts`
  - Commands run:
    - `npx @insforge/cli functions deploy storage-upload-url`
    - `npx @insforge/cli functions invoke storage-upload-url --method GET`
    - `npx @insforge/cli functions list`
  - Parity result:
    - Returns `success`, `uploadUrl`, and `path` as required.
    - Additional fields (`method`, `fields`, `confirmRequired`, `confirmUrl`, `expiresAt`) included for S3 upload-strategy compatibility.
  - Legacy archive action completed:
    - Moved `routes/storageRoutes.js` -> `temp/legacy-backend/routes/storageRoutes.js`
    - Moved `controllers/storageController.js` -> `temp/legacy-backend/controllers/storageController.js`
    - Updated `server.js` to remove archived storage route import/use.
  - Next required step: implement meetings list function migration.
- 2026-04-01: Completed Phase 3 slice for meetings endpoints.
  - Function sources created:
    - `insforge/functions/meetings-list/index.ts`
    - `insforge/functions/meeting-detail/index.ts`
  - Commands run:
    - `npx @insforge/cli functions deploy meetings-list`
    - `npx @insforge/cli functions deploy meeting-detail`
    - `npx @insforge/cli functions invoke meetings-list --method GET`
    - `npx @insforge/cli db query "insert into public.meetings ... returning id"`
    - `npx @insforge/cli functions invoke meeting-detail --method POST --data '{"id":"<seeded-id>"}'`
  - Parity result:
    - `meetings-list` returns `{ success: true, data: [] }` shape and supports `limit`/`offset` query.
    - `meeting-detail` returns `{ success: true, data: meeting }` shape with nested `action_items`.
  - Legacy archive action completed:
    - Moved `routes/meetingRoutes.js` -> `temp/legacy-backend/routes/meetingRoutes.js`
    - Moved `controllers/meetingController.js` -> `temp/legacy-backend/controllers/meetingController.js`
    - Updated `server.js` to remove archived meetings route import/use.
  - Next required step: migrate `POST /api/v1/audio/process` and async worker flow.
- 2026-04-01: Completed Phase 3 slice for audio processing endpoints.
  - Function sources created:
    - `insforge/functions/audio-process/index.ts`
    - `insforge/functions/audio-worker/index.ts`
  - Commands run:
    - `npx @insforge/cli functions deploy audio-process`
    - `npx @insforge/cli functions deploy audio-worker`
    - `npx @insforge/cli functions invoke audio-process --method POST --data '{"path":"..."}'`
    - `npx @insforge/cli functions invoke audio-worker --method POST --data '{"meetingId":"..."}'`
    - `npx @insforge/cli schedules create --name "audio-worker-cron" --cron "*/2 * * * *" ...`
    - `npx @insforge/cli logs function.logs --limit 5`
  - Parity result:
    - `audio-process` returns `202` semantics with `{ success, message, meetingId }`.
    - Worker marks meetings as `failed` on processing errors.
    - Failure path verified in DB and logs.
  - Legacy archive action completed:
    - Moved `routes/audioRoutes.js` -> `temp/legacy-backend/routes/audioRoutes.js`
    - Moved `controllers/audioController.js` -> `temp/legacy-backend/controllers/audioController.js`
    - Moved services -> `temp/legacy-backend/services/*`
    - Updated `server.js` to remove archived audio route import/use.
  - Reliability add-on:
    - Created schedule `audio-worker-cron` (every 2 minutes) to process pending meetings.
  - Remaining validation:
    - Run one happy-path test with a real uploaded audio object to confirm `completed` + `action_items` insertion.
- 2026-04-01: Completed happy-path E2E validation and final archival.
  - E2E outcome:
    - Uploaded `test2.mp3` using returned upload strategy and confirmation flow.
    - Triggered `audio-process`, processed with `audio-worker`, and verified `meetings.status = completed`.
    - Verified `intelligence_data` persisted in DB.
    - `action_items` remained empty for this sample (valid when no action tasks are extracted).
  - Final archival action:
    - Moved `server.js` -> `temp/legacy-backend/server.js`
  - Integration doc created:
    - `insforge/function-endpoint-map.md`

---

## Immediate Next Actions (Next Execution Session)
1. [x] Update frontend base URL + endpoint paths to InsForge functions using `insforge/function-endpoint-map.md`.
2. [ ] Run frontend smoke test for create/list/detail meeting flow.
3. [ ] Produce final migration report with rollback notes and operational checklist.
4. [ ] Optionally tighten auth by replacing `DUMMY_USER_ID` with token-derived user identity.

Latest update (2026-04-01):
- Frontend API client migrated in `meeting_app/lib/core/api_service.dart`:
  - Old `/api/v1/*` routes replaced with InsForge function URLs.
  - Upload logic updated to support upload strategy (`presigned` and `direct`) and optional `confirm-upload`.
  - Meetings list and detail now call `meetings-list` and `meeting-detail` functions.

Latest update (2026-04-02):
- Supabase decommissioning completed for active stack:
  - Deleted InsForge secrets: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`.
  - Removed Supabase variables from local `.env`.
  - Removed root dependency `@supabase/supabase-js`.
  - Updated InsForge docs/checklists to reflect fully InsForge-native runtime.