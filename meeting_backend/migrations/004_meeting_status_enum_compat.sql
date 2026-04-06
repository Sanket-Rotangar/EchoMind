-- Compatibility migration for databases where meetings.status uses enum type public.meeting_status
-- and still contains only legacy values (e.g. processing/completed/failed).

ALTER TABLE public.meetings
  ADD COLUMN IF NOT EXISTS transcript_text TEXT,
  ADD COLUMN IF NOT EXISTS failure_reason TEXT;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'meetings'
      AND column_name = 'status'
      AND udt_name = 'meeting_status'
  ) THEN
    ALTER TABLE public.meetings
      ALTER COLUMN status TYPE TEXT
      USING status::text;
  END IF;
END
$$;

UPDATE public.meetings
SET status = 'uploaded'
WHERE status::text = 'processing';

CREATE TABLE IF NOT EXISTS public.meeting_state_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  meeting_id UUID NOT NULL REFERENCES public.meetings(id) ON DELETE CASCADE,
  stage TEXT NOT NULL,
  details JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_meeting_state_events_meeting_created_at
  ON public.meeting_state_events (meeting_id, created_at DESC);
