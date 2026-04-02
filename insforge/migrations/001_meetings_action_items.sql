CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS public.meetings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  title TEXT NOT NULL DEFAULT 'Processing Meeting...',
  status TEXT NOT NULL DEFAULT 'processing' CHECK (status IN ('processing', 'completed', 'failed')),
  audio_storage_path TEXT,
  intelligence_data JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
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

ALTER TABLE public.meetings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.action_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS meetings_select_own ON public.meetings;
CREATE POLICY meetings_select_own
ON public.meetings
FOR SELECT
TO authenticated
USING (user_id = auth.uid());

DROP POLICY IF EXISTS meetings_insert_own ON public.meetings;
CREATE POLICY meetings_insert_own
ON public.meetings
FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS meetings_update_own ON public.meetings;
CREATE POLICY meetings_update_own
ON public.meetings
FOR UPDATE
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS meetings_delete_own ON public.meetings;
CREATE POLICY meetings_delete_own
ON public.meetings
FOR DELETE
TO authenticated
USING (user_id = auth.uid());

DROP POLICY IF EXISTS action_items_select_own ON public.action_items;
CREATE POLICY action_items_select_own
ON public.action_items
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.meetings m
    WHERE m.id = action_items.meeting_id
      AND m.user_id = auth.uid()
  )
);

DROP POLICY IF EXISTS action_items_insert_own ON public.action_items;
CREATE POLICY action_items_insert_own
ON public.action_items
FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.meetings m
    WHERE m.id = action_items.meeting_id
      AND m.user_id = auth.uid()
  )
);

DROP POLICY IF EXISTS action_items_update_own ON public.action_items;
CREATE POLICY action_items_update_own
ON public.action_items
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.meetings m
    WHERE m.id = action_items.meeting_id
      AND m.user_id = auth.uid()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.meetings m
    WHERE m.id = action_items.meeting_id
      AND m.user_id = auth.uid()
  )
);

DROP POLICY IF EXISTS action_items_delete_own ON public.action_items;
CREATE POLICY action_items_delete_own
ON public.action_items
FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.meetings m
    WHERE m.id = action_items.meeting_id
      AND m.user_id = auth.uid()
  )
);
