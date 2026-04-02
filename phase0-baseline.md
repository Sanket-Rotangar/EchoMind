# Phase 0 Baseline — API Contract & Parity Matrix

Date: 2026-04-01
Scope: Existing Express backend contract to be preserved during InsForge migration.

## 1) Canonical API Contract (Current Behavior)

## `GET /api/v1/storage/upload-url`
Purpose:
- Returns a signed upload URL and generated storage `path`.

Request:
- Method: `GET`
- Body: none
- Query: none

Success Response:
- Status: `200`
- Body:
```json
{
  "success": true,
  "uploadUrl": "<signed-upload-url>",
  "path": "<timestamp>-<random8chars>"
}
```

Error Response:
- Status: `500`
- Body:
```json
{
  "success": false,
  "message": "Failed to generate upload URL"
}
```

---

## `POST /api/v1/audio/process`
Purpose:
- Creates a processing meeting row, returns `202` immediately, and runs AI pipeline asynchronously.

Request:
- Method: `POST`
- Headers: `Content-Type: application/json`
- Body:
```json
{
  "path": "<storage-object-path>"
}
```

Success Response:
- Status: `202`
- Body:
```json
{
  "success": true,
  "message": "Audio received. Processing in background.",
  "meetingId": "<uuid>"
}
```

Error Response:
- Status: `500`
- Body:
```json
{
  "success": false,
  "message": "<error-message>"
}
```

Background side-effects:
1. Creates placeholder meeting row with `status = processing`.
2. Transcribes audio from signed download URL.
3. Extracts insights from Gemini.
4. Updates meeting row with `status = completed` + `intelligence_data`.
5. Inserts `action_items` from `action_matrix`.
6. On error sets `status = failed`.

---

## `GET /api/v1/meetings`
Purpose:
- Returns paginated meeting cards for the active user.

Request:
- Method: `GET`
- Query (optional):
  - `limit` (default `8`)
  - `offset` (default `0`)

Success Response:
- Status: `200`
- Body:
```json
{
  "success": true,
  "data": [
    {
      "id": "<uuid>",
      "title": "<string>",
      "status": "processing|completed|failed",
      "created_at": "<timestamp>"
    }
  ]
}
```

Error Response:
- Status: `500`
- Body:
```json
{
  "success": false,
  "message": "<error-message>"
}
```

---

## `GET /api/v1/meetings/:id`
Purpose:
- Returns full meeting with related action items.

Request:
- Method: `GET`
- Path param: `id`

Success Response:
- Status: `200`
- Body:
```json
{
  "success": true,
  "data": {
    "id": "<uuid>",
    "title": "<string>",
    "status": "processing|completed|failed",
    "audio_storage_path": "<string>",
    "intelligence_data": {
      "bottom_line": "<string>",
      "decisions_register": ["..."],
      "action_matrix": [{ "assignee": "...", "task": "...", "deadline": "..." }],
      "risks_and_blockers": ["..."],
      "key_metrics": ["..."]
    },
    "action_items": [
      {
        "id": "<uuid>",
        "meeting_id": "<uuid>",
        "assignee": "<string>",
        "task_description": "<string>",
        "deadline": "<string|null>"
      }
    ]
  }
}
```

Error Response:
- Status: `500`
- Body:
```json
{
  "success": false,
  "message": "<error-message>"
}
```

---

## Optional Legacy Endpoint — `POST /api/v1/audio/upload`
Purpose:
- Multipart upload from local file, sync processing, immediate insights response.

Request:
- Method: `POST`
- Content-Type: `multipart/form-data`
- Form field: `meeting_audio` (file)

Success Response:
- Status: `200`
- Body:
```json
{
  "success": true,
  "data": {
    "bottom_line": "<string>",
    "decisions_register": ["..."],
    "action_matrix": [{ "assignee": "...", "task": "...", "deadline": "..." }],
    "risks_and_blockers": ["..."],
    "key_metrics": ["..."]
  }
}
```

Error Response:
- Status: `500`
- Body:
```json
{
  "success": false,
  "message": "Failed to process audio"
}
```

## Decision (Phase 0)
- Decision: **Retire after migration** (do not migrate as primary InsForge endpoint).
- Rationale: frontend flow already supports signed upload + async process path, which scales better and fits InsForge-native architecture.
- Transition rule: keep legacy Express endpoint alive until InsForge parity tests pass for required endpoints.

---

## 2) Endpoint Parity Matrix

| Endpoint | Priority | Must Preserve | Migration Status | Validation Rule |
|---|---|---|---|---|
| `GET /api/v1/storage/upload-url` | P0 | status code, response keys, path format intent | Pending | response has `success`, `uploadUrl`, `path` |
| `POST /api/v1/audio/process` | P0 | `202`, `meetingId`, async side-effects | Pending | immediate 202 + DB row transitions |
| `GET /api/v1/meetings` | P0 | pagination params, response shape | Pending | sorted list, limit/offset behavior |
| `GET /api/v1/meetings/:id` | P0 | full meeting + action_items relation | Pending | includes nested `action_items` |
| `POST /api/v1/audio/upload` | Optional | sync insights response | Planned retire | no frontend dependency before removal |

---

## 3) Phase 0 Completion Checklist

- [x] Existing API contracts documented.
- [x] Endpoint parity checklist created.
- [x] Decision documented for legacy upload endpoint.
- [ ] Final sign-off from stakeholder before Phase 1 execution.
