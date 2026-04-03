import unittest
import httpx

import main


class TestMeetingBackendE2E(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.original_validate_config = main.config.validate_config
        self.original_insert_meeting = main.db_client.insert_meeting
        self.original_generate_upload_url = main.db_client.generate_upload_url
        self.original_get_meetings = main.db_client.get_meetings
        self.original_get_meeting_detail = main.db_client.get_meeting_detail
        self.original_process_audio_task = main.assembly_service.process_audio_task
        self.original_extract_insights_task = main.ai_service.extract_insights_task
        self.original_webhook_secret = main.config.WEBHOOK_SECRET

        main.config.validate_config = lambda: None
        main.config.WEBHOOK_SECRET = "test-webhook-secret"

        self.audio_task_calls = []
        self.ai_task_calls = []

        async def fake_generate_upload_url(_path):
            return "https://example.com/upload"

        async def fake_get_meetings(user_id, limit=8, offset=0):
            return [{"id": "meeting-1", "title": "Test", "status": "processing", "created_at": "2026-04-04T10:00:00Z"}]

        async def fake_get_meeting_detail(user_id, meeting_id):
            if meeting_id == "missing":
                return {}
            return {"id": meeting_id, "title": "Test", "status": "completed", "action_items": []}

        async def fake_insert_meeting(user_id, path):
            return {
                "id": "meeting-123",
                "audio_storage_path": path,
                "user_id": user_id,
            }

        async def fake_process_audio_task(meeting_id, audio_storage_path):
            self.audio_task_calls.append((meeting_id, audio_storage_path))

        async def fake_extract_insights_task(meeting_id, transcript_id, status, body):
            self.ai_task_calls.append((meeting_id, transcript_id, status, body))

        main.db_client.insert_meeting = fake_insert_meeting
        main.db_client.generate_upload_url = fake_generate_upload_url
        main.db_client.get_meetings = fake_get_meetings
        main.db_client.get_meeting_detail = fake_get_meeting_detail
        main.assembly_service.process_audio_task = fake_process_audio_task
        main.ai_service.extract_insights_task = fake_extract_insights_task

    def tearDown(self):
        main.config.validate_config = self.original_validate_config
        main.db_client.insert_meeting = self.original_insert_meeting
        main.db_client.generate_upload_url = self.original_generate_upload_url
        main.db_client.get_meetings = self.original_get_meetings
        main.db_client.get_meeting_detail = self.original_get_meeting_detail
        main.assembly_service.process_audio_task = self.original_process_audio_task
        main.ai_service.extract_insights_task = self.original_extract_insights_task
        main.config.WEBHOOK_SECRET = self.original_webhook_secret

    async def make_request(self, method, url, **kwargs):
        transport = httpx.ASGITransport(app=main.app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            return await client.request(method, url, **kwargs)

    async def test_health_endpoint(self):
        response = await self.make_request("GET", "/health")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["status"], "ok")

    async def test_process_meeting_requires_user_header(self):
        response = await self.make_request("POST", "/api/meetings/process", json={"path": "audio/test.mp3"})

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()["detail"], "x-user-id header is required")

    async def test_process_meeting_success_triggers_background_task(self):
        response = await self.make_request(
            "POST",
            "/api/meetings/process",
            headers={"x-user-id": "user-1"},
            json={"path": "audio/test.mp3"},
        )

        self.assertEqual(response.status_code, 202)
        body = response.json()
        self.assertTrue(body["success"])
        self.assertEqual(body["meetingId"], "meeting-123")
        self.assertEqual(self.audio_task_calls, [("meeting-123", "audio/test.mp3")])

    async def test_storage_upload_url_endpoint(self):
        response = await self.make_request(
            "GET",
            "/api/v1/storage/upload-url",
            headers={"x-user-id": "user-1"},
        )
        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertTrue(body["success"])
        self.assertTrue(body["uploadUrl"].startswith("https://"))
        self.assertTrue(body["path"].endswith(".m4a"))

    async def test_get_meetings_endpoint(self):
        response = await self.make_request(
            "GET",
            "/api/v1/meetings?limit=8&offset=0",
            headers={"x-user-id": "user-1"},
        )
        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertTrue(body["success"])
        self.assertEqual(len(body["data"]), 1)

    async def test_get_meeting_detail_not_found(self):
        response = await self.make_request(
            "GET",
            "/api/v1/meetings/missing",
            headers={"x-user-id": "user-1"},
        )
        self.assertEqual(response.status_code, 404)

    async def test_get_meeting_detail_success(self):
        response = await self.make_request(
            "GET",
            "/api/v1/meetings/meeting-1",
            headers={"x-user-id": "user-1"},
        )
        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertTrue(body["success"])
        self.assertEqual(body["data"]["id"], "meeting-1")

    async def test_webhook_rejects_invalid_token(self):
        response = await self.make_request(
            "POST",
            "/api/webhooks/assemblyai?meetingId=meeting-1&token=wrong-token",
            json={"transcript_id": "tr-1", "status": "completed"},
        )

        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.json()["detail"], "Unauthorized webhook token")

    async def test_webhook_success_triggers_ai_task(self):
        payload = {"transcript_id": "tr-1", "status": "completed"}
        response = await self.make_request(
            "POST",
            "/api/webhooks/assemblyai?meetingId=meeting-1&token=test-webhook-secret",
            json=payload,
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["success"], True)
        self.assertEqual(self.ai_task_calls, [("meeting-1", "tr-1", "completed", payload)])


if __name__ == "__main__":
    unittest.main()
