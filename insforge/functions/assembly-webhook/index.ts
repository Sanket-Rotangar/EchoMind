import { createClient } from 'npm:@insforge/sdk';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization, x-webhook-token',
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

export default async function handler(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return json({ success: false, message: 'Method not allowed' }, 405);
  }

  const baseUrl        = Deno.env.get('INSFORGE_BASE_URL');
  const apiKey         = Deno.env.get('API_KEY');
  const assemblyApiKey = Deno.env.get('ASSEMBLYAI_API_KEY');
  const webhookSecret  = Deno.env.get('WEBHOOK_SECRET');

  if (!baseUrl || !apiKey || !assemblyApiKey || !webhookSecret) {
    return json({ success: false, message: 'Server configuration error' }, 500);
  }

  // Auth: secret now arrives in header, not URL
  const incomingToken = req.headers.get('x-webhook-token');
  if (!incomingToken || incomingToken !== webhookSecret) {
    return json({ success: false, message: 'Unauthorized' }, 401);
  }

  const url       = new URL(req.url);
  const meetingId = url.searchParams.get('meetingId');

  if (!meetingId) {
    return json({ success: false, message: 'meetingId query param is required' }, 400);
  }

  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    return json({ success: false, message: 'Invalid JSON body' }, 400);
  }

  const transcriptId  = (payload?.transcript_id ?? payload?.id ?? null) as string | null;
  const webhookStatus = (payload?.status ?? null) as string | null;

  if (!transcriptId) {
    return json({ success: false, message: 'transcript_id is required' }, 400);
  }

  const client = createClient({ baseUrl, edgeFunctionToken: apiKey });

  try {
    const { data: meeting, error: meetingError } = await client.database
      .from('meetings')
      .select('id, stage')
      .eq('id', meetingId)
      .single();

    if (meetingError || !meeting) {
      return json({ success: false, message: meetingError?.message ?? 'Meeting not found' }, 404);
    }

    // Already past this point — AssemblyAI retried, nothing to do
    if (['transcribed', 'extracting', 'completed'].includes(meeting.stage)) {
      return json({ success: true, meetingId, message: 'Already processed' }, 200);
    }

    // AssemblyAI reported an error
    if (webhookStatus === 'error') {
      await client.database
        .from('meetings')
        .update({ status: 'failed', stage: 'failed', last_error: String(payload?.error ?? 'AssemblyAI error') })
        .eq('id', meetingId);
      return json({ success: false, meetingId, message: 'Transcription failed at AssemblyAI' }, 500);
    }

    // Intermediate status (queued, processing) — just acknowledge
    if (webhookStatus && webhookStatus !== 'completed') {
      return json({ success: true, meetingId, message: `Acknowledged status: ${webhookStatus}` }, 200);
    }

    // Status is 'completed' — fetch the full transcript from AssemblyAI
    const transcriptRes = await fetch(`https://api.assemblyai.com/v2/transcript/${transcriptId}`, {
      headers: { authorization: assemblyApiKey },
    });

    if (!transcriptRes.ok) {
      const detail = await transcriptRes.text();
      throw new Error(`AssemblyAI fetch failed: ${detail}`);
    }

    const transcriptPayload = await transcriptRes.json();

    if (transcriptPayload.status === 'error') {
      await client.database
        .from('meetings')
        .update({ status: 'failed', stage: 'failed', last_error: transcriptPayload.error ?? 'Transcription error' })
        .eq('id', meetingId);
      return json({ success: false, meetingId, message: 'Transcription failed' }, 500);
    }

    if (transcriptPayload.status !== 'completed') {
      return json({ success: true, meetingId, message: `Transcript not ready: ${transcriptPayload.status}` }, 202);
    }

    // Build transcript array
    const utterances: Array<{ speaker?: string; text?: string }> =
      Array.isArray(transcriptPayload.utterances) ? transcriptPayload.utterances : [];

    const transcriptArray: string[] = utterances.length > 0
      ? utterances.map((u) => `Speaker ${u.speaker ?? 'Unknown'}: ${u.text ?? ''}`)
      : [String(transcriptPayload.text ?? '')];

    // Atomic stage claim: only advance from 'transcribing' → 'transcribed'
    // Saves raw transcript in the same update so Gemini retries never need AssemblyAI again
    const { data: claimed, error: claimError } = await client.database
      .from('meetings')
      .update({
        stage: 'transcribed',
        raw_transcript: transcriptArray,
        last_attempted_at: new Date().toISOString(),
      })
      .eq('id', meetingId)
      .eq('stage', 'transcribing')
      .select('id');

    if (claimError) {
      throw new Error(claimError.message);
    }

    if (!claimed || claimed.length === 0) {
      // Another webhook invocation already claimed this — safe to ignore
      return json({ success: true, meetingId, message: 'Stage already claimed' }, 200);
    }

    // Fire-and-forget: hand off to extract-intelligence
    fetch(`${baseUrl}/functions/extract-intelligence`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ meetingId }),
    }).catch(() => {/* cron will pick up transcribed meetings if this fails */});

    return json({ success: true, meetingId, transcriptId, message: 'Transcript saved. Extraction queued.' }, 200);

  } catch (err) {
    const message = err instanceof Error ? err.message : 'assembly-webhook failed';

    // Do not mark as failed here — stage stays 'transcribing' so cron can retry
    await client.database
      .from('meetings')
      .update({ last_error: message })
      .eq('id', meetingId)
      .in('stage', ['transcribing']);

    return json({ success: false, meetingId, message }, 500);
  }
}
