-- Meeting Groups: allows users to organize meetings into groups
-- and chat about meetings within a specific group.

CREATE TABLE IF NOT EXISTS public.meeting_groups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.meeting_group_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id UUID NOT NULL REFERENCES public.meeting_groups(id) ON DELETE CASCADE,
  meeting_id UUID NOT NULL REFERENCES public.meetings(id) ON DELETE CASCADE,
  added_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT unique_group_meeting UNIQUE (group_id, meeting_id)
);

CREATE INDEX IF NOT EXISTS idx_meeting_groups_user_id
  ON public.meeting_groups (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_meeting_group_members_group_id
  ON public.meeting_group_members (group_id);

CREATE INDEX IF NOT EXISTS idx_meeting_group_members_meeting_id
  ON public.meeting_group_members (meeting_id);

-- Reuse the existing set_updated_at() trigger function
DROP TRIGGER IF EXISTS trg_meeting_groups_set_updated_at ON public.meeting_groups;
CREATE TRIGGER trg_meeting_groups_set_updated_at
BEFORE UPDATE ON public.meeting_groups
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();
