# End-to-End Workflow Test Checklist

This checklist validates the migrated InsForge backend + Flutter frontend flow.

## 0) Preconditions

- Linked InsForge project is active.
- Functions are deployed: `storage-upload-url`, `audio-process`, `audio-worker`, `meetings-list`, `meeting-detail`.
- Schedule exists: `audio-worker-cron`.
- Secrets configured in InsForge:
  - `ASSEMBLYAI_API_KEY`
  - `GEMINI_API_KEY`
  - `DUMMY_USER_ID`
  - `ANON_KEY`
  - `API_KEY`

## 1) Quick Backend Health

```bash
npx @insforge/cli functions list
npx @insforge/cli schedules list
npx @insforge/cli diagnose
```

Expected:
- All required functions are `active`.
- `audio-worker-cron` appears and is `Active: Yes`.

## 2) Manual API Sanity Checks

### 2.1 Storage Upload Strategy

```bash
npx @insforge/cli functions invoke storage-upload-url --method GET
```

Expected response contains:
- `success: true`
- `uploadUrl`
- `path`

### 2.2 Meetings List

```bash
npx @insforge/cli functions invoke meetings-list --method GET
```

Expected:
- `success: true`
- `data` array

## 3) Full Audio Pipeline Test (Backend)

Use the provided sample or your own audio file:
- `test2.mp3` in repo root

Steps:
1. Get upload strategy from `storage-upload-url`.
2. Upload file using returned strategy (`presigned` form upload or direct upload).
3. Confirm upload if `confirmRequired=true`.
4. Call `audio-process` with returned `path`.
5. Run `audio-worker` manually for immediate validation (or wait for cron).
6. Verify meeting row has `status=completed` and `intelligence_data`.

Verification SQL:

```bash
npx @insforge/cli db query "select id, status, intelligence_data is not null as has_intelligence_data from public.meetings order by created_at desc limit 5;"
npx @insforge/cli db query "select meeting_id, count(*) as action_count from public.action_items group by meeting_id order by action_count desc limit 10;"
```

Notes:
- `action_items` may be empty if transcript has no extractable tasks.

## 4) Flutter App Test

## 4.1 Required run-time define

`meeting_app/lib/core/api_service.dart` expects:
- `INSFORGE_ANON_KEY`

Run app with:

```bash
cd meeting_app
flutter run --dart-define=INSFORGE_ANON_KEY=<your_insforge_anon_key>
```

## 4.2 In-app flow

1. Open app and upload/record a meeting audio.
2. Confirm immediate processing acknowledgement.
3. Go to Home list and check new meeting appears.
4. Refresh/poll after processing and verify status changes to `completed`.
5. Open meeting details and verify summary data loads.

## 5) Failure Path Test

Trigger with invalid path:

```bash
npx @insforge/cli functions invoke audio-process --method POST --data '{"path":"invalid/nonexistent-audio"}'
```

Then run worker once:

```bash
npx @insforge/cli functions invoke audio-worker --method POST --data '{"meetingId":"<meeting-id-from-above>"}'
```

Verify DB:

```bash
npx @insforge/cli db query "select id, status from public.meetings where id = '<meeting-id-from-above>';"
```

Expected: `status = failed`

## 6) Observability

```bash
npx @insforge/cli logs function.logs --limit 20
```

Expected:
- Recent worker/function execution entries are visible.
