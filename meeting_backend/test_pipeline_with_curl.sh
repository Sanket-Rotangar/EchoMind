#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:8000}"
AUDIO_FILE="${1:-/home/sanket-rotangar/Desktop/MeetingApp/test-audio.m4a}"
USER_ID="${USER_ID:-6f3f7d34-2c17-4ea8-9d43-48fb5ef6c2b2}"
POLL_INTERVAL_SECS="${POLL_INTERVAL_SECS:-5}"
MAX_POLLS="${MAX_POLLS:-36}"

if [[ ! -f "$AUDIO_FILE" ]]; then
  echo "Audio file not found: $AUDIO_FILE"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required. Install with: sudo apt-get install -y jq"
  exit 1
fi

echo "[1/5] Requesting signed upload URL..."
UPLOAD_RESP="$(curl -sS -f -H "x-user-id: $USER_ID" "$BASE_URL/api/v1/storage/upload-url")"
echo "$UPLOAD_RESP" | jq

UPLOAD_URL="$(echo "$UPLOAD_RESP" | jq -r '.uploadUrl')"
AUDIO_PATH="$(echo "$UPLOAD_RESP" | jq -r '.path')"

if [[ -z "$UPLOAD_URL" || "$UPLOAD_URL" == "null" ]]; then
  echo "Failed to get uploadUrl"
  exit 1
fi

if [[ -z "$AUDIO_PATH" || "$AUDIO_PATH" == "null" ]]; then
  echo "Failed to get path"
  exit 1
fi

echo "[2/5] Uploading audio to Supabase signed URL..."
curl -sS -f -X PUT \
  -H "Content-Type: audio/m4a" \
  --data-binary "@$AUDIO_FILE" \
  "$UPLOAD_URL" >/tmp/meeting_upload_response.json || {
    echo "Upload failed"
    exit 1
  }

if [[ -s /tmp/meeting_upload_response.json ]]; then
  echo "Upload response:"
  cat /tmp/meeting_upload_response.json
else
  echo "Upload completed (empty response body)"
fi

echo "[3/5] Triggering backend processing..."
PROCESS_HTTP="$(curl -sS -o /tmp/meeting_process_response.json -w "%{http_code}" -X POST \
  -H "Content-Type: application/json" \
  -H "x-user-id: $USER_ID" \
  -d "{\"path\":\"$AUDIO_PATH\"}" \
  "$BASE_URL/api/meetings/process")"

echo "Process HTTP status: $PROCESS_HTTP"
cat /tmp/meeting_process_response.json | jq

if [[ "$PROCESS_HTTP" -lt 200 || "$PROCESS_HTTP" -ge 300 ]]; then
  echo "Process request failed. Check backend logs for DB/API details."
  exit 1
fi

PROCESS_RESP="$(cat /tmp/meeting_process_response.json)"

MEETING_ID="$(echo "$PROCESS_RESP" | jq -r '.meetingId')"
if [[ -z "$MEETING_ID" || "$MEETING_ID" == "null" ]]; then
  echo "Failed to get meetingId from process response"
  exit 1
fi

echo "[4/5] Polling meeting state and recent state events..."
for ((i=1; i<=MAX_POLLS; i++)); do
  DETAIL_RESP="$(curl -sS -f -H "x-user-id: $USER_ID" "$BASE_URL/api/v1/meetings/$MEETING_ID")"
  STATUS="$(echo "$DETAIL_RESP" | jq -r '.data.status')"
  TITLE="$(echo "$DETAIL_RESP" | jq -r '.data.title')"

  echo "Poll #$i => status=$STATUS title=$TITLE"
  echo "$DETAIL_RESP" | jq '{
    id: .data.id,
    status: .data.status,
    assembly_transcript_id: .data.assembly_transcript_id,
    failure_reason: .data.failure_reason,
    latest_events: (.data.meeting_state_events // [] | sort_by(.created_at) | reverse | .[:5])
  }'

  if [[ "$STATUS" == "completed" || "$STATUS" == "failed" ]]; then
    break
  fi

  sleep "$POLL_INTERVAL_SECS"
done

echo "[5/5] Final meeting payload (full):"
curl -sS -f -H "x-user-id: $USER_ID" "$BASE_URL/api/v1/meetings/$MEETING_ID" | jq

echo "Done. Meeting ID: $MEETING_ID"
