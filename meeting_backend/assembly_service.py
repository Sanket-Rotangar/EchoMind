import httpx
import db_client
import config
from urllib.parse import urlencode
import logging

logger = logging.getLogger(__name__)

async def process_audio_task(meeting_id: str, audio_path: str):
    logger.info(f"[PIPELINE][ASSEMBLY] start meeting={meeting_id} path={audio_path}")
    
    try:
        signed_url = await db_client.generate_signed_url(audio_path)
        if not signed_url:
            raise Exception("Failed to generate signed URL")
        logger.info(f"[PIPELINE][ASSEMBLY] signed-url-ready meeting={meeting_id}")
            
        params = {"meetingId": meeting_id, "token": config.WEBHOOK_SECRET}
        webhook_url = f"{config.WEBHOOK_PUBLIC_BASE_URL}/api/webhooks/assemblyai?{urlencode(params)}"
        
        async with httpx.AsyncClient() as client:
            headers = {"authorization": config.ASSEMBLYAI_API_KEY}
            body = {
                "audio_url": signed_url,
                "speaker_labels": True,
                "speech_models": ["universal-2"],
                "webhook_url": webhook_url
            }
            resp = await client.post("https://api.assemblyai.com/v2/transcript", json=body, headers=headers)
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
            logger.info(f"[PIPELINE][ASSEMBLY] transcript-submitted meeting={meeting_id} transcript={data.get('id')}")
            
        try:
            await db_client.update_meeting(meeting_id, {
                "assembly_transcript_id": data["id"],
                "status": "processing"
            })
        except Exception as update_error:
            logger.warning(
                "[PIPELINE][ASSEMBLY] meeting update with transcript_id failed meeting=%s error=%s; retrying status-only update",
                meeting_id,
                update_error,
            )
            await db_client.update_meeting(meeting_id, {"status": "processing"})
        
        logger.info(f"[PIPELINE][ASSEMBLY] queued meeting={meeting_id}")
    except Exception as e:
        logger.error(f"[PIPELINE][ASSEMBLY] failed meeting={meeting_id} error={e}")
        await db_client.update_meeting(meeting_id, {"status": "failed"})
