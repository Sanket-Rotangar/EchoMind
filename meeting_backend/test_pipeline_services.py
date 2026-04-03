import unittest
from unittest.mock import AsyncMock, Mock, patch

import assembly_service
import ai_service


class TestAssemblyService(unittest.IsolatedAsyncioTestCase):
    async def test_process_audio_task_success(self):
        with patch.object(assembly_service.db_client, "generate_signed_url", AsyncMock(return_value="https://signed-url")), \
             patch.object(assembly_service.db_client, "update_meeting", AsyncMock()) as update_meeting:

            mock_response = Mock()
            mock_response.raise_for_status.return_value = None
            mock_response.json.return_value = {"id": "tr-123"}

            mock_client = AsyncMock()
            mock_client.post.return_value = mock_response

            class ClientCtx:
                async def __aenter__(self_inner):
                    return mock_client

                async def __aexit__(self_inner, exc_type, exc, tb):
                    return False

            with patch("assembly_service.httpx.AsyncClient", return_value=ClientCtx()):
                await assembly_service.process_audio_task("meeting-1", "audio/test.mp3")

            update_meeting.assert_awaited_once_with(
                "meeting-1",
                {"assembly_transcript_id": "tr-123", "status": "processing"},
            )

    async def test_process_audio_task_failure_sets_failed(self):
        with patch.object(assembly_service.db_client, "generate_signed_url", AsyncMock(return_value=None)), \
             patch.object(assembly_service.db_client, "update_meeting", AsyncMock()) as update_meeting:
            await assembly_service.process_audio_task("meeting-2", "audio/test.mp3")
            update_meeting.assert_awaited_once_with("meeting-2", {"status": "failed"})


class TestAIService(unittest.IsolatedAsyncioTestCase):
    async def test_extract_insights_error_status_sets_failed(self):
        with patch.object(ai_service.db_client, "update_meeting", AsyncMock()) as update_meeting:
            await ai_service.extract_insights_task("meeting-1", "tr-1", "error", {})
            update_meeting.assert_awaited_once_with("meeting-1", {"status": "failed"})

    async def test_extract_insights_completed_updates_meeting_and_actions(self):
        transcript_payload = {
            "status": "completed",
            "utterances": [
                {"speaker": "A", "text": "We will ship by Friday"},
                {"speaker": "B", "text": "Ravi will update docs"},
            ],
        }

        mock_response = Mock()
        mock_response.raise_for_status.return_value = None
        mock_response.json.return_value = transcript_payload

        mock_client = AsyncMock()
        mock_client.get.return_value = mock_response

        class ClientCtx:
            async def __aenter__(self_inner):
                return mock_client

            async def __aexit__(self_inner, exc_type, exc, tb):
                return False

        class FakeModel:
            def __init__(self, *_args, **_kwargs):
                pass

            def generate_content(self, *_args, **_kwargs):
                class Resp:
                    text = (
                        '{"bottom_line":"Release planning","decisions_register":["Ship Friday"],'
                        '"action_matrix":[{"assignee":"Ravi","task":"Update docs","deadline":"Friday"}],'
                        '"risks_and_blockers":["None"],"key_metrics":["ETA Friday"]}'
                    )

                return Resp()

        with patch("ai_service.httpx.AsyncClient", return_value=ClientCtx()), \
             patch.object(ai_service.genai, "GenerativeModel", FakeModel), \
             patch.object(ai_service.db_client, "update_meeting", AsyncMock()) as update_meeting, \
             patch.object(ai_service.db_client, "replace_action_items", AsyncMock()) as replace_action_items:

            await ai_service.extract_insights_task("meeting-1", "tr-1", "completed", {})

            update_meeting.assert_awaited_once()
            replace_action_items.assert_awaited_once()


if __name__ == "__main__":
    unittest.main()
