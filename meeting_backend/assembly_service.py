import httpx
import db_client
import config
import ai_service
from urllib.parse import urlencode
import logging
import asyncio
import uuid

logger = logging.getLogger(__name__)


async def _poll_for_transcript_completion(meeting_id: str, transcript_id: str, run_id: str):
    max_attempts = 36
    interval_seconds = 10

    async with httpx.AsyncClient() as client:
        headers = {"authorization": config.ASSEMBLYAI_API_KEY}
        for attempt in range(1, max_attempts + 1):
            meeting = await db_client.get_meeting_by_id(meeting_id)
            current_status = (meeting or {}).get("status")
            if current_status and current_status != "transcribing":
                logger.info(
                    "[PIPELINE][ASSEMBLY] poll-exit meeting=%s reason=status-changed status=%s",
                    meeting_id,
                    current_status,
                )
                return

            resp = await client.get(
                f"https://api.assemblyai.com/v2/transcript/{transcript_id}",
                headers=headers,
            )
            resp.raise_for_status()
            data = resp.json()
            assembly_status = data.get("status")
            error_msg = data.get("error")
            logger.info(
                "[PIPELINE][ASSEMBLY] poll meeting=%s run_id=%s transcript=%s attempt=%s status=%s",
                meeting_id,
                run_id,
                transcript_id,
                attempt,
                assembly_status,
            )

            # Log error details if status is error
            if assembly_status == "error":
                logger.error(
                    "[PIPELINE][ASSEMBLY] transcription-error meeting=%s transcript=%s error=%s",
                    meeting_id,
                    transcript_id,
                    error_msg or "unknown error",
                )

            if assembly_status in {"completed", "error"}:
                await ai_service.extract_insights_task(
                    meeting_id,
                    transcript_id,
                    assembly_status,
                    {"source": "assembly_poll", "attempt": attempt, "run_id": run_id},
                )
                return

            await asyncio.sleep(interval_seconds)

    logger.warning(
        "[PIPELINE][ASSEMBLY] poll-timeout meeting=%s transcript=%s attempts=%s",
        meeting_id,
        transcript_id,
        max_attempts,
    )


async def process_audio_task(
    meeting_id: str,
    audio_path: str,
    trigger_source: str = "initial_upload",
):
    run_id = uuid.uuid4().hex
    logger.info(
        "[PIPELINE][ASSEMBLY] start meeting=%s run_id=%s source=%s path=%s",
        meeting_id,
        run_id,
        trigger_source,
        audio_path,
    )

    try:
        signed_url = await db_client.generate_signed_url(audio_path)
        if not signed_url:
            raise Exception("Failed to generate signed URL")
        logger.info(f"[PIPELINE][ASSEMBLY] signed-url-ready meeting={meeting_id}")

        params = {
            "meetingId": meeting_id,
            "token": config.WEBHOOK_SECRET,
            "runId": run_id,
        }
        webhook_url = f"{config.WEBHOOK_PUBLIC_BASE_URL}/api/webhooks/assemblyai?{urlencode(params)}"

        async with httpx.AsyncClient() as client:
            headers = {"authorization": config.ASSEMBLYAI_API_KEY}
            body = {
                "audio_url": signed_url,
                "speaker_labels": True,
                "speech_models": ["universal-2"],
                "webhook_url": webhook_url,
            }
            resp = await client.post(
                "https://api.assemblyai.com/v2/transcript", json=body, headers=headers
            )
            if resp.status_code >= 400:
                logger.error(
                    "[PIPELINE][ASSEMBLY] submit-error meeting=%s status=%s response=%s audio_url_prefix=%s webhook_url=%s",
                    meeting_id,
                    resp.status_code,
                    resp.text,
                    signed_url[:120],
                    webhook_url,
                )
                resp.raise_for_status()
            data = resp.json()
            logger.info(
                f"[PIPELINE][ASSEMBLY] transcript-submitted meeting={meeting_id} transcript={data.get('id')}"
            )

        await db_client.transition_meeting_state(
            meeting_id,
            "transcribing",
            details={
                "run_id": run_id,
                "trigger_source": trigger_source,
                "audio_path": audio_path,
                "assembly_transcript_id": data.get("id"),
                "webhook_url": webhook_url,
            },
            extra_updates={"assembly_transcript_id": data["id"]},
        )

        await _poll_for_transcript_completion(meeting_id, data["id"], run_id)

        logger.info(f"[PIPELINE][ASSEMBLY] queued meeting={meeting_id}")
    except Exception as e:
        logger.error(f"[PIPELINE][ASSEMBLY] failed meeting={meeting_id} error={e}")
        await db_client.transition_meeting_state(
            meeting_id,
            "failed",
            details={
                "stage": "assembly_submit",
                "run_id": run_id,
                "trigger_source": trigger_source,
                "error": str(e),
            },
            extra_updates={"failure_reason": f"assembly_submit: {e}"},
        )
