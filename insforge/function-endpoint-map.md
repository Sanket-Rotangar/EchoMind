# InsForge Function Endpoint Map

Base host:
- `https://nm5x7yfa.ap-southeast.insforge.app/functions`

## Legacy -> InsForge Mapping

- `GET /api/v1/storage/upload-url`
  - New: `GET /functions/storage-upload-url`

- `GET /api/v1/meetings?limit=<n>&offset=<n>`
  - New: `GET /functions/meetings-list?limit=<n>&offset=<n>`

- `GET /api/v1/meetings/:id`
  - New: `GET /functions/meeting-detail?id=<meetingId>`

- `POST /api/v1/audio/process`
  - New: `POST /functions/audio-process`
  - Body: `{ "path": "<storage-object-path>" }`

## Worker Endpoint (Internal)

- `POST /functions/audio-worker`
  - Used by `audio-process` (fire-and-forget) and by scheduled cron `audio-worker-cron`.
  - Optional body: `{ "meetingId": "<uuid>" }` for targeted processing.

## Current Scheduling

- Schedule name: `audio-worker-cron`
- Cron: `*/2 * * * *`
- URL: `https://nm5x7yfa.ap-southeast.insforge.app/functions/audio-worker`

## Frontend Integration Notes

1. Replace old backend base URL with:
   - `https://nm5x7yfa.ap-southeast.insforge.app/functions`
2. Keep response parsing same for `success`, `data`, and `meetingId` fields.
3. For meeting detail API, pass `id` as query param.
4. Keep the same signed upload flow:
   - Call `storage-upload-url`
   - Upload using returned strategy
   - Confirm upload if `confirmRequired=true`
   - Call `audio-process` with returned `path`
