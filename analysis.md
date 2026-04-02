# Backend Analysis – MeetingApp

> Legacy snapshot note (2026-04-02): this document analyzes the old Express + Supabase backend before InsForge migration. Current runtime architecture is documented in `insforge.md`.

> Scope analyzed: Node.js backend only (`server.js`, `controllers/`, `routes/`, `services/`).
> Excluded: Flutter frontend in `meeting_app/`.

## 1) High-Level Overview

This backend is an ingestion and meeting-intelligence API built with Express.

Core responsibilities:
- Receive/upload meeting audio.
- Generate signed Supabase storage upload URLs.
- Transcribe audio using AssemblyAI.
- Extract structured meeting insights using Gemini.
- Persist meeting records and action items in Supabase.
- Serve meeting list/detail APIs for the client.

The system has **two processing modes**:
1. **Synchronous local upload flow** (`/api/v1/audio/upload`) for direct file upload + immediate result.
2. **Asynchronous cloud flow** (`/api/v1/audio/process`) that returns quickly (`202`) and completes AI processing in background.

---

## 2) Backend Structure

- `server.js` → App bootstrap, middleware, route mounting, port listener.
- `routes/`
  - `audioRoutes.js` → audio upload/process endpoints.
  - `storageRoutes.js` → signed upload URL endpoint.
  - `meetingRoutes.js` → list/detail meeting endpoints.
- `controllers/`
  - `audioController.js` → audio ingestion orchestration + async pipeline trigger.
  - `storageController.js` → signed upload URL generation.
  - `meetingController.js` → fetch meeting list/details.
- `services/`
  - `assemblyService.js` → AssemblyAI transcription wrappers.
  - `geminiService.js` → Gemini structured extraction with schema.
  - `supabaseService.js` → storage URL, meetings CRUD, action-items persistence.

---

## 3) Runtime and Dependencies

From `package.json`:
- `express` (5.2.1)
- `cors`
- `multer`
- `assemblyai`
- `@google/generative-ai`
- `@supabase/supabase-js`
- `dotenv`

Observations:
- API server is minimal and clear.
- No testing framework configured (`npm test` is placeholder).
- No linting/formatting scripts in root backend package.

---

## 4) Request Flow and Endpoint Behavior

## 4.1 Global Middleware

- `cors()` enabled globally.
- `express.json()` enabled globally.
- Routes mounted without path prefixes in `server.js`; each route file defines full endpoint path.

## 4.2 Endpoints

### `POST /api/v1/audio/upload`
Defined in `routes/audioRoutes.js`.

- Uses `multer` disk storage with destination `uploads/`.
- Expects multipart field: `meeting_audio`.
- Flow (`controllers/audioController.js`):
  1. Validate file exists.
  2. Transcribe local file via AssemblyAI (`transcribeAudio`).
  3. Extract insights via Gemini (`extractMeetingInsights`).
  4. Return insights in response.
  5. Cleanup uploaded file in `finally` block.

Response style:
- Success: `200 { success: true, data: insights }`
- Error: `500 { success: false, message: "Failed to process audio" }`

### `POST /api/v1/audio/process`
Defined in `routes/audioRoutes.js`.

- Expects JSON body with `path` (Supabase object path).
- Uses `DUMMY_USER_ID` from environment.
- Flow:
  1. Create placeholder meeting row (`status: processing`).
  2. Immediately return `202` + `meetingId`.
  3. Start background pipeline (not awaited):
     - Signed download URL from Supabase storage.
     - Transcribe via AssemblyAI from URL.
     - Extract insights via Gemini.
     - Update meeting row + insert action items.
     - On failure mark row `status: failed`.

Response style:
- Accepted: `202 { success: true, message, meetingId }`
- Error: `500 { success: false, message }`

### `GET /api/v1/storage/upload-url`
Defined in `routes/storageRoutes.js`.

- Generates random path (`<timestamp>-<random8chars>`).
- Returns signed upload URL from Supabase bucket `meetings`.

Response style:
- Success: `200 { success: true, uploadUrl, path }`
- Error: `500 { success: false, message }`

### `GET /api/v1/meetings`
Defined in `routes/meetingRoutes.js`.

- Query params:
  - `limit` default `8`
  - `offset` default `0`
- Uses `DUMMY_USER_ID` and fetches meetings ordered by `created_at desc`.

Response style:
- Success: `200 { success: true, data: meetings }`
- Error: `500 { success: false, message }`

### `GET /api/v1/meetings/:id`
Defined in `routes/meetingRoutes.js`.

- Fetches one meeting and related `action_items` via Supabase relationship select.

Response style:
- Success: `200 { success: true, data: meeting }`
- Error: `500 { success: false, message }`

---

## 5 Data and Service Design

## 5.1 AssemblyAI service (`services/assemblyService.js`)

- Requires `ASSEMBLYAI_API_KEY` on startup.
- Provides:
  - `transcribeAudio(filePath)`
  - `transcribeAudioFromUrl(audioUrl)`
- Both return normalized utterance array:
  - `Speaker <id>: <text>`

## 5.2 Gemini service (`services/geminiService.js`)

- Uses `gemini-2.5-flash` with strict JSON schema.
- Extracted fields:
  - `bottom_line`
  - `decisions_register[]`
  - `action_matrix[]` (assignee, task, deadline)
  - `risks_and_blockers[]`
  - `key_metrics[]`
- Returns parsed JSON object.

Strength:
- Structured schema-driven output reduces parsing ambiguity.

## 5.3 Supabase service (`services/supabaseService.js`)

Storage operations:
- Create signed upload URL (`createSignedUploadUrl`).
- Create signed download URL (`createSignedUrl`).

DB operations:
- Insert placeholder meeting in processing state.
- Update completed meeting with `intelligence_data` and derived title.
- Insert `action_items` from `action_matrix`.
- Mark meeting failed.
- Paginated list by user.
- Single meeting with related action items.

---

## 6 Environment Variables Required

Detected from code:
- `PORT` (optional, default 3000)
- `ASSEMBLYAI_API_KEY`
- `GEMINI_API_KEY`
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY` (checked but not used in client creation)
- `SUPABASE_SERVICE_ROLE_KEY` (used in `createClient`)
- `DUMMY_USER_ID`

---

## 7 Strengths

- Clear modular separation: routes → controllers → services.
- Practical async architecture for heavy processing (`202 Accepted` + background pipeline).
- File cleanup after synchronous upload reduces disk bloat.
- Schema-constrained LLM output improves consistency.
- Meeting lifecycle status model (`processing`, `completed`, `failed`) is frontend-friendly.

---

## 8 Risks / Gaps Identified

## 8.1 Authentication and Authorization
- No real auth middleware.
- Uses `DUMMY_USER_ID` globally, so all requests operate as a single user identity.
- `GET /meetings/:id` has no ownership check in controller/service layer.

## 8.2 Input Validation
- Minimal validation for:
  - `path` in `/audio/process`.
  - `limit`/`offset` in `/meetings` (negative or huge values not constrained).
  - `:id` format in `/meetings/:id`.
- No file type/size checks configured in multer.

## 8.3 Error Handling and Observability
- No centralized error middleware.
- Mixed console logging, no structured logger/correlation IDs.
- Background task failures are logged but no retry/dead-letter strategy.

## 8.4 Background Processing Model
- Background pipeline runs in-process without queue.
- If process crashes/restarts, in-flight job is lost.
- Limited scalability for concurrent long-running transcriptions.

## 8.5 Security Considerations
- Global permissive CORS default.
- Service role key is loaded in app process (expected for backend) but safeguards around endpoint abuse are minimal.
- Signed upload URL endpoint is public in current form.

## 8.6 Minor Code-Level Issues
- `supabaseService.js` validates `SUPABASE_ANON_KEY` but creates client with `SUPABASE_SERVICE_ROLE_KEY`; startup check should validate what is actually used.
- `title` derivation can produce `"undefined..."` if `bottom_line` missing (schema usually prevents this, but defensive code is recommended).

---

## 9 Performance and Scalability Notes

Current design is suitable for MVP/small workloads.

Bottlenecks at scale:
- In-process background jobs.
- Sequential AI pipeline per meeting.
- No explicit rate limiting/backoff handling for AssemblyAI/Gemini API limits.

Recommended scale path:
- Move background pipeline to queue worker (BullMQ/SQS/etc.).
- Persist job state and retries.
- Add API rate limiting and request size guards.

---

## 10) Recommended Prioritized Improvements

## Priority 0 (Must-have before production)
1. Add auth (JWT/session) and derive `user_id` from token instead of `DUMMY_USER_ID`.
2. Add authorization checks for meeting ownership on detail API.
3. Add robust input validation (schema validator like Zod/Joi).
4. Restrict CORS origins and add basic rate limiting.
5. Validate `SUPABASE_SERVICE_ROLE_KEY` explicitly at startup.

## Priority 1 (Reliability)
1. Move background processing to a durable queue worker.
2. Add retry policy + failure reasons persisted in DB.
3. Add centralized error middleware and structured logs.

## Priority 2 (Quality)
1. Add tests for controller/service happy/error paths.
2. Add linting + formatting scripts.
3. Add API documentation (OpenAPI/Swagger).

---

## 11) Backend Readiness Summary

- **Architecture clarity:** Good
- **Feature completeness for MVP:** Good
- **Production security posture:** Low (until auth/authorization/validation are added)
- **Scalability posture:** Moderate-to-low (until queue-based workers are introduced)
- **Maintainability:** Good baseline, would benefit from tests and standardized error/logging patterns

Overall: the backend is well-structured for MVP development and demonstrates a clean ingestion-to-insight flow, but requires authentication, input hardening, and durable async processing to be production-ready.
