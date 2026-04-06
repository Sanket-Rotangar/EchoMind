CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS public.meetings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  title TEXT NOT NULL DEFAULT 'Processing Meeting...',
  status TEXT NOT NULL DEFAULT 'uploaded' CHECK (status IN ('uploaded', 'transcribing', 'transcribed', 'analyzing', 'completed', 'failed')),
  audio_storage_path TEXT NOT NULL,
  assembly_transcript_id TEXT,
  transcript_text TEXT,
  intelligence_data JSONB,
  failure_reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT unique_user_audio_path UNIQUE (user_id, audio_storage_path)
);

CREATE TABLE IF NOT EXISTS public.meeting_state_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  meeting_id UUID NOT NULL REFERENCES public.meetings(id) ON DELETE CASCADE,
  stage TEXT NOT NULL,
  details JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.action_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  meeting_id UUID NOT NULL REFERENCES public.meetings(id) ON DELETE CASCADE,
  assignee TEXT NOT NULL,
  task_description TEXT NOT NULL,
  deadline TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_meetings_user_created_at
  ON public.meetings (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_meetings_status
  ON public.meetings (status);

CREATE INDEX IF NOT EXISTS idx_action_items_meeting_id
  ON public.action_items (meeting_id);

CREATE INDEX IF NOT EXISTS idx_meeting_state_events_meeting_created_at
  ON public.meeting_state_events (meeting_id, created_at DESC);

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_meetings_set_updated_at ON public.meetings;
CREATE TRIGGER trg_meetings_set_updated_at
BEFORE UPDATE ON public.meetings
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_action_items_set_updated_at ON public.action_items;
CREATE TRIGGER trg_action_items_set_updated_at
BEFORE UPDATE ON public.action_items
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();
