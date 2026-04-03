ALTER TABLE public.meetings
ADD COLUMN IF NOT EXISTS assembly_transcript_id TEXT;
