import httpx
import google.generativeai as genai
import db_client
import calendar_service
import config
import logging
import json

logger = logging.getLogger(__name__)
genai.configure(api_key=config.GEMINI_API_KEY)


async def extract_insights_task(
    meeting_id: str, transcript_id: str, status: str, webhook_payload: dict
):
    run_id = str(
        (webhook_payload or {}).get("run_id")
        or (webhook_payload or {}).get("runId")
        or "unknown"
    )

    logger.info(
        f"[PIPELINE][GEMINI] start meeting={meeting_id} run_id={run_id} transcript={transcript_id} status={status}"
    )

    meeting = await db_client.get_meeting_by_id(meeting_id)
    if meeting and meeting.get("status") in {"completed", "failed"}:
        logger.info(
            "[PIPELINE][GEMINI] skip meeting=%s reason=terminal-status status=%s",
            meeting_id,
            meeting.get("status"),
        )
        return

    if status == "error":
        logger.error(f"[PIPELINE][GEMINI] webhook status error meeting={meeting_id}")
        await db_client.transition_meeting_state(
            meeting_id,
            "failed",
            details={
                "stage": "assembly_webhook",
                "run_id": run_id,
                "webhook_payload": webhook_payload,
            },
            extra_updates={"failure_reason": "assembly_webhook:error"},
        )
        return

    try:
        async with httpx.AsyncClient() as client:
            headers = {"authorization": config.ASSEMBLYAI_API_KEY}
            resp = await client.get(
                f"https://api.assemblyai.com/v2/transcript/{transcript_id}",
                headers=headers,
            )
            resp.raise_for_status()
            transcript_data = resp.json()
            logger.info(
                f"[PIPELINE][GEMINI] transcript-fetched meeting={meeting_id} assemblyStatus={transcript_data.get('status')}"
            )

        if transcript_data.get("status") == "error":
            await db_client.transition_meeting_state(
                meeting_id,
                "failed",
                details={
                    "stage": "assembly_fetch",
                    "run_id": run_id,
                    "assembly_status": "error",
                    "transcript_id": transcript_id,
                },
                extra_updates={"failure_reason": "assembly_fetch:error"},
            )
            return

        if transcript_data.get("status") != "completed":
            logger.error(
                f"Unexpected transcript status for {meeting_id}: {transcript_data.get('status')}"
            )
            await db_client.transition_meeting_state(
                meeting_id,
                "failed",
                details={
                    "stage": "assembly_fetch",
                    "run_id": run_id,
                    "assembly_status": transcript_data.get("status"),
                    "transcript_id": transcript_id,
                },
                extra_updates={
                    "failure_reason": f"assembly_fetch:unexpected_status:{transcript_data.get('status')}"
                },
            )
            return

        utterances = transcript_data.get("utterances", [])
        if utterances:
            transcript_lines = [
                f"Speaker {u.get('speaker', 'Unknown')}: {u.get('text', '')}"
                for u in utterances
            ]
        else:
            transcript_lines = [transcript_data.get("text", "")]

        transcript_text = "\n".join(transcript_lines)
        snapshot_text = transcript_text[:20000]
        logger.info(
            f"[PIPELINE][GEMINI] transcript-ready meeting={meeting_id} lines={len(transcript_lines)}"
        )

        await db_client.insert_meeting_event(
            meeting_id,
            "transcript_snapshot",
            details={
                "run_id": run_id,
                "transcript_id": transcript_id,
                "line_count": len(transcript_lines),
                "transcript_text": snapshot_text,
            },
        )

        await db_client.transition_meeting_state(
            meeting_id,
            "transcribed",
            details={
                "run_id": run_id,
                "transcript_id": transcript_id,
                "line_count": len(transcript_lines),
            },
            extra_updates={"transcript_text": transcript_text},
        )

        await db_client.transition_meeting_state(
            meeting_id,
            "analyzing",
            details={
                "run_id": run_id,
                "model": "gemini-2.5-flash",
                "transcript_id": transcript_id,
            },
        )

        model = genai.GenerativeModel("gemini-2.5-flash")
        prompt = f"""
        Analyze this meeting transcript. Extract the core objective, definitive action items, and deadlines.
        Do not invent data. Resolve pronouns to specific speakers.
        
        IMPORTANT - For deadlines in action_matrix:
        - Look for ANY date/time mentioned in relation to tasks, reviews, follow-ups, or deliverables.
        - If a review meeting or follow-up is scheduled, that IS the deadline for related tasks.
        - Include specific dates (e.g., "April 16, 2024") and times (e.g., "10 AM", "2:30 PM") when mentioned.
        - Use relative dates if specific dates aren't given (e.g., "next Monday", "end of week", "tomorrow").
        - Only set deadline to null if absolutely NO timeframe is mentioned or implied for that task.
        
        Examples of deadlines to extract:
        - "Let's meet on April 16 at 10 AM to review" -> deadline: "April 16 at 10 AM"
        - "Have this done by Friday" -> deadline: "Friday"
        - "We need this by end of week" -> deadline: "end of week"
        - "Complete before the next standup" -> deadline: "next standup"
        
        Respond with a JSON object matching this schema exactly:
        {{
          "bottom_line": "string - one sentence summary of the meeting",
          "decisions_register": ["string - each decision made"],
          "action_matrix": [
            {{ "assignee": "string - person responsible", "task": "string - what needs to be done", "deadline": "string or null - when it's due (extract from context, include time if mentioned)" }}
          ],
          "risks_and_blockers": ["string - any risks or blockers mentioned"],
          "key_metrics": ["string - any numbers or metrics mentioned"]
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

        await db_client.insert_meeting_event(
            meeting_id,
            "analysis_snapshot",
            details={
                "run_id": run_id,
                "transcript_id": transcript_id,
                "summary": str(insights.get("bottom_line", "")),
                "intelligence_data": insights,
            },
        )

        title = insights.get("bottom_line", "Untitled Meeting")
        title_str = str(title) if title else "Untitled Meeting"
        if len(title_str) > 40:
            title_str = title_str[:40] + "..."

        await db_client.transition_meeting_state(
            meeting_id,
            "completed",
            details={
                "run_id": run_id,
                "transcript_id": transcript_id,
                "action_item_count": len(insights.get("action_matrix", [])),
            },
            extra_updates={
                "title": title_str,
                "intelligence_data": insights,
            },
        )
        logger.info(f"[PIPELINE][GEMINI] meeting-completed meeting={meeting_id}")

        actions = insights.get("action_matrix", [])
        logger.info(f"[PIPELINE][GEMINI] action_matrix from AI: {actions}")

        if actions and isinstance(actions, list):
            action_rows = []
            for act in actions:
                if isinstance(act, dict):
                    action_rows.append(
                        {
                            "meeting_id": meeting_id,
                            "assignee": str(act.get("assignee", "Unassigned")),
                            "task_description": str(act.get("task", "")),
                            "deadline": str(act.get("deadline", ""))
                            if act.get("deadline")
                            else None,
                        }
                    )

            if action_rows:
                await db_client.replace_action_items(meeting_id, action_rows)
                logger.info(
                    f"[PIPELINE][GEMINI] action-items-updated meeting={meeting_id} count={len(action_rows)}"
                )

        # Add action items with deadlines to Google Calendar if user has connected
        await _add_to_calendar(meeting_id, title_str, actions)

        logger.info(f"[PIPELINE][GEMINI] success meeting={meeting_id}")
    except Exception as e:
        logger.error(f"[PIPELINE][GEMINI] failed meeting={meeting_id} error={e}")
        await db_client.transition_meeting_state(
            meeting_id,
            "failed",
            details={
                "stage": "gemini_analyze",
                "run_id": run_id,
                "error": str(e),
                "transcript_id": transcript_id,
            },
            extra_updates={"failure_reason": f"gemini_analyze: {e}"},
        )


async def _add_to_calendar(meeting_id: str, meeting_title: str, actions: list):
    """Add action items with deadlines to user's Google Calendar."""
    try:
        # Get the meeting to find the user
        meeting = await db_client.get_meeting_by_id(meeting_id)
        if not meeting:
            logger.warning(f"[CALENDAR] Meeting not found: {meeting_id}")
            return

        user_id = meeting.get("user_id")
        if not user_id:
            logger.warning(f"[CALENDAR] No user_id for meeting: {meeting_id}")
            return

        # Check if user has calendar connected
        user = await db_client.get_user_by_id(user_id)
        if not user:
            logger.warning(f"[CALENDAR] User not found: {user_id}")
            return

        if not user.get("calendar_connected"):
            logger.info(f"[CALENDAR] Calendar not connected for user: {user_id}")
            return

        calendar_tokens = user.get("calendar_tokens")
        if not calendar_tokens:
            logger.warning(f"[CALENDAR] No calendar tokens for user: {user_id}")
            return

        # Add events to calendar
        created_events = await calendar_service.add_meeting_events_to_calendar(
            user_tokens=calendar_tokens,
            meeting_title=meeting_title,
            action_items=actions,
            meeting_id=meeting_id,
        )

        if created_events:
            logger.info(
                f"[CALENDAR] Created {len(created_events)} calendar events for meeting={meeting_id}"
            )
        else:
            logger.info(
                f"[CALENDAR] No calendar events created for meeting={meeting_id} (no valid deadlines)"
            )

    except Exception as e:
        # Don't fail the whole pipeline if calendar integration fails
        logger.error(
            f"[CALENDAR] Failed to add calendar events for meeting={meeting_id}: {e}"
        )
