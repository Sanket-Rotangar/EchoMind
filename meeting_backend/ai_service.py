import httpx
import google.generativeai as genai
import db_client
import config
import logging
import json

logger = logging.getLogger(__name__)
genai.configure(api_key=config.GEMINI_API_KEY)

async def extract_insights_task(meeting_id: str, transcript_id: str, status: str, webhook_payload: dict):
    logger.info(f"[PIPELINE][GEMINI] start meeting={meeting_id} transcript={transcript_id} status={status}")
    
    if status == "error":
        logger.error(f"[PIPELINE][GEMINI] webhook status error meeting={meeting_id}")
        await db_client.update_meeting(meeting_id, {"status": "failed"})
        return
        
    try:
        async with httpx.AsyncClient() as client:
            headers = {"authorization": config.ASSEMBLYAI_API_KEY}
            resp = await client.get(f"https://api.assemblyai.com/v2/transcript/{transcript_id}", headers=headers)
            resp.raise_for_status()
            transcript_data = resp.json()
            logger.info(f"[PIPELINE][GEMINI] transcript-fetched meeting={meeting_id} assemblyStatus={transcript_data.get('status')}")
            
        if transcript_data.get("status") == "error":
            await db_client.update_meeting(meeting_id, {"status": "failed"})
            return
            
        if transcript_data.get("status") != "completed":
            logger.error(f"Unexpected transcript status for {meeting_id}: {transcript_data.get('status')}")
            await db_client.update_meeting(meeting_id, {"status": "failed"})
            return
            
        utterances = transcript_data.get("utterances", [])
        if utterances:
            transcript_lines = [f"Speaker {u.get('speaker', 'Unknown')}: {u.get('text', '')}" for u in utterances]
        else:
            transcript_lines = [transcript_data.get("text", "")]
            
        transcript_text = "\n".join(transcript_lines)
        logger.info(f"[PIPELINE][GEMINI] transcript-ready meeting={meeting_id} lines={len(transcript_lines)}")
        
        model = genai.GenerativeModel('gemini-2.5-flash')
        prompt = f"""
        Analyze this meeting transcript. Extract the core objective, definitive action items, and deadlines.
        Do not invent data. Resolve pronouns to specific speakers.
        
        Respond with a JSON object matching this schema exactly:
        {{
          "bottom_line": "string",
          "decisions_register": ["string"],
          "action_matrix": [
            {{ "assignee": "string", "task": "string", "deadline": "string or null" }}
          ],
          "risks_and_blockers": ["string"],
          "key_metrics": ["string"]
        }}
        
        TRANSCRIPT:
        {transcript_text}
        """
        
        response = model.generate_content(prompt)
        logger.info(f"[PIPELINE][GEMINI] model-response meeting={meeting_id}")
        
        raw_text = (response.text or "").strip()
        if raw_text.startswith("```json"):
            raw_text = raw_text[7:]
        if raw_text.endswith("```"):
            raw_text = raw_text[:-3]

        if not raw_text.strip():
            raise ValueError("Gemini returned empty response")
        
        insights = json.loads(raw_text.strip())
        logger.info(f"[PIPELINE][GEMINI] json-parse-success meeting={meeting_id}")
        
        title = insights.get("bottom_line", "Untitled Meeting")
        title_str = str(title) if title else "Untitled Meeting"
        if len(title_str) > 40:
            title_str = title_str[:40] + "..."
            
        await db_client.update_meeting(meeting_id, {
            "title": title_str,
            "status": "completed",
            "intelligence_data": insights
        })
        logger.info(f"[PIPELINE][GEMINI] meeting-completed meeting={meeting_id}")
        
        actions = insights.get("action_matrix", [])
        if actions and isinstance(actions, list):
            action_rows = []
            for act in actions:
                if isinstance(act, dict):
                    action_rows.append({
                        "meeting_id": meeting_id,
                        "assignee": str(act.get("assignee", "Unassigned")),
                        "task_description": str(act.get("task", "")),
                        "deadline": str(act.get("deadline", "")) if act.get("deadline") else None
                    })
            
            if action_rows:
                await db_client.replace_action_items(meeting_id, action_rows)
                logger.info(f"[PIPELINE][GEMINI] action-items-updated meeting={meeting_id} count={len(action_rows)}")
            
        logger.info(f"[PIPELINE][GEMINI] success meeting={meeting_id}")
    except Exception as e:
        logger.error(f"[PIPELINE][GEMINI] failed meeting={meeting_id} error={e}")
        await db_client.update_meeting(meeting_id, {"status": "failed"})
