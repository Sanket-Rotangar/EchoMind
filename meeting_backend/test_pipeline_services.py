import unittest
from unittest.mock import AsyncMock, Mock, patch

import assembly_service
import ai_service


class TestAssemblyService(unittest.IsolatedAsyncioTestCase):
    async def test_process_audio_task_success(self):
        with patch.object(assembly_service.db_client, "generate_signed_url", AsyncMock(return_value="https://signed-url")), \
             patch.object(assembly_service.db_client, "transition_meeting_state", AsyncMock()) as transition_meeting_state, \
             patch.object(assembly_service, "_poll_for_transcript_completion", AsyncMock()) as poll_for_completion:

            mock_response = Mock()
            mock_response.status_code = 200
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

            transition_meeting_state.assert_awaited_once_with(
                "meeting-1",
                "transcribing",
                details={
                    "audio_path": "audio/test.mp3",
                    "assembly_transcript_id": "tr-123",
                    "webhook_url": unittest.mock.ANY,
                },
                extra_updates={"assembly_transcript_id": "tr-123"},
            )
            poll_for_completion.assert_awaited_once_with("meeting-1", "tr-123")

    async def test_process_audio_task_failure_sets_failed(self):
        with patch.object(assembly_service.db_client, "generate_signed_url", AsyncMock(return_value=None)), \
             patch.object(assembly_service.db_client, "transition_meeting_state", AsyncMock()) as transition_meeting_state:
            await assembly_service.process_audio_task("meeting-2", "audio/test.mp3")
            transition_meeting_state.assert_awaited_once()
            args, kwargs = transition_meeting_state.await_args
            self.assertEqual(args[0], "meeting-2")
            self.assertEqual(args[1], "failed")
            self.assertIn("assembly_submit", kwargs["details"]["stage"])


class TestAIService(unittest.IsolatedAsyncioTestCase):
    async def test_extract_insights_error_status_sets_failed(self):
        with patch.object(ai_service.db_client, "get_meeting_by_id", AsyncMock(return_value={"status": "transcribing"})), \
             patch.object(ai_service.db_client, "transition_meeting_state", AsyncMock()) as transition_meeting_state:
            await ai_service.extract_insights_task("meeting-1", "tr-1", "error", {})
            transition_meeting_state.assert_awaited_once()
            args, _kwargs = transition_meeting_state.await_args
            self.assertEqual(args[0], "meeting-1")
            self.assertEqual(args[1], "failed")

    async def test_extract_insights_skips_when_terminal(self):
        with patch.object(ai_service.db_client, "get_meeting_by_id", AsyncMock(return_value={"status": "completed"})), \
             patch.object(ai_service.db_client, "transition_meeting_state", AsyncMock()) as transition_meeting_state:
            await ai_service.extract_insights_task("meeting-1", "tr-1", "completed", {})
            transition_meeting_state.assert_not_awaited()

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
               patch.object(ai_service.db_client, "get_meeting_by_id", AsyncMock(return_value={"status": "transcribing"})), \
             patch.object(ai_service.db_client, "transition_meeting_state", AsyncMock()) as transition_meeting_state, \
             patch.object(ai_service.db_client, "replace_action_items", AsyncMock()) as replace_action_items:

            await ai_service.extract_insights_task("meeting-1", "tr-1", "completed", {})

            self.assertEqual(transition_meeting_state.await_count, 3)
            self.assertEqual(transition_meeting_state.await_args_list[0].args[1], "transcribed")
            self.assertEqual(transition_meeting_state.await_args_list[1].args[1], "analyzing")
            self.assertEqual(transition_meeting_state.await_args_list[2].args[1], "completed")
            replace_action_items.assert_awaited_once()


if __name__ == "__main__":
    unittest.main()
