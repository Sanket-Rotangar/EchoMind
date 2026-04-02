-- Add stage column to drive the pipeline state machine
ALTER TABLE public.meetings
  ADD COLUMN IF NOT EXISTS stage TEXT NOT NULL DEFAULT 'pending'
    CHECK (stage IN ('pending', 'transcribing', 'transcribed', 'extracting', 'completed', 'failed'));

-- Store AssemblyAI transcript ID once submitted (idempotency key)
ALTER TABLE public.meetings
  ADD COLUMN IF NOT EXISTS assembly_transcript_id TEXT;

-- Store raw transcript array so Gemini retries never call AssemblyAI again
ALTER TABLE public.meetings
  ADD COLUMN IF NOT EXISTS raw_transcript JSONB;

-- Retry tracking per meeting
ALTER TABLE public.meetings
  ADD COLUMN IF NOT EXISTS retry_count INTEGER NOT NULL DEFAULT 0;

ALTER TABLE public.meetings
  ADD COLUMN IF NOT EXISTS last_error TEXT;

ALTER TABLE public.meetings
  ADD COLUMN IF NOT EXISTS last_attempted_at TIMESTAMPTZ;

-- Prevent duplicate meetings for the same audio file per user
ALTER TABLE public.meetings
  ADD CONSTRAINT IF NOT EXISTS unique_user_audio_path
    UNIQUE (user_id, audio_storage_path);

-- Atomic commit function: updates meeting + replaces action_items in one transaction
-- Called from extract-intelligence edge function
CREATE OR REPLACE FUNCTION public.commit_meeting_results(
  p_meeting_id  UUID,
  p_insights    JSONB,
  p_title       TEXT
) RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE public.meetings
  SET
    status           = 'completed',
    stage            = 'completed',
    title            = p_title,
    intelligence_data = p_insights,
    updated_at       = now()
  WHERE id = p_meeting_id;

  DELETE FROM public.action_items
  WHERE meeting_id = p_meeting_id;

  INSERT INTO public.action_items (meeting_id, assignee, task_description, deadline)
  SELECT
    p_meeting_id,
    COALESCE(item->>'assignee', 'Unassigned'),
    COALESCE(item->>'task', ''),
    NULLIF(item->>'deadline', '')
  FROM jsonb_array_elements(p_insights->'action_matrix') AS item;
END;
$$;
