import { createClient } from 'npm:@insforge/sdk';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

const isPublicWebhookHost = (hostname: string): boolean => {
  const h = hostname.toLowerCase();
  if (h === 'localhost' || h.endsWith('.localhost') || h.endsWith('.local') || h === '::1') {
    return false;
  }
  const ipv4 = h.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (!ipv4) return true;
  const [a, b, c] = ipv4.slice(1).map(Number);
  if (a === 127 || a === 10) return false;
  if (a === 192 && b === 168) return false;
  if (a === 172 && b >= 16 && b <= 31) return false;
  return true;
};

const resolveWebhookBaseUrl = (): string => {
  const raw = Deno.env.get('WEBHOOK_PUBLIC_BASE_URL') ?? Deno.env.get('INSFORGE_BASE_URL');
  if (!raw) throw new Error('WEBHOOK_PUBLIC_BASE_URL or INSFORGE_BASE_URL is required');
  const parsed = new URL(raw);
  if (!['https:', 'http:'].includes(parsed.protocol)) {
    throw new Error('Webhook base URL must use http or https');
  }
  if (!isPublicWebhookHost(parsed.hostname)) {
    throw new Error(`Webhook host is not publicly reachable: ${parsed.hostname}`);
  }
  return parsed.origin;
};

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

  let meetingId: string;
  try {
    const body = await req.json();
    meetingId = typeof body?.meetingId === 'string' ? body.meetingId.trim() : '';
  } catch {
    return json({ success: false, message: 'Invalid JSON body' }, 400);
  }

  if (!meetingId) {
    return json({ success: false, message: 'meetingId is required' }, 400);
  }

  const client = createClient({ baseUrl, edgeFunctionToken: apiKey });

  try {
    // Fetch meeting — include assembly_transcript_id for idempotency check
    const { data: meeting, error: fetchError } = await client.database
      .from('meetings')
      .select('id, stage, audio_storage_path, assembly_transcript_id')
      .eq('id', meetingId)
      .single();

    if (fetchError || !meeting) {
      return json({ success: false, message: fetchError?.message ?? 'Meeting not found' }, 404);
    }

    // Already past this stage — nothing to do
    if (['transcribing', 'transcribed', 'extracting', 'completed'].includes(meeting.stage)) {
      return json({ success: true, meetingId, message: `Stage already at: ${meeting.stage}` }, 200);
    }

    // Idempotency: already submitted to AssemblyAI
    if (meeting.assembly_transcript_id) {
      return json({ success: true, meetingId, message: 'Already submitted to AssemblyAI' }, 200);
    }

    const audioPath = typeof meeting.audio_storage_path === 'string'
      ? meeting.audio_storage_path.trim()
      : '';

    if (!audioPath) {
      await client.database
        .from('meetings')
        .update({ status: 'failed', stage: 'failed', last_error: 'audio_storage_path is missing' })
        .eq('id', meetingId);
      return json({ success: false, message: 'audio_storage_path is missing' }, 500);
    }

    // Atomic stage claim: only advance if still at 'pending'
    const { data: claimed, error: claimError } = await client.database
      .from('meetings')
      .update({
        stage: 'transcribing',
        last_attempted_at: new Date().toISOString(),
      })
      .eq('id', meetingId)
      .eq('stage', 'pending')
      .select('id');

    if (claimError) {
      return json({ success: false, message: claimError.message }, 500);
    }

    // Another invocation already claimed this stage
    if (!claimed || claimed.length === 0) {
      return json({ success: true, meetingId, message: 'Stage already claimed by another invocation' }, 200);
    }

    // Get a temporary download URL for the audio file
    const encodedKey = encodeURIComponent(audioPath);
    const strategyRes = await fetch(
      `${baseUrl}/api/storage/buckets/meetings/objects/${encodedKey}/download-strategy`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ expiresIn: 3600 }),
      },
    );

    if (!strategyRes.ok) {
      const detail = await strategyRes.text();
      throw new Error(`Download strategy failed: ${detail}`);
    }

    const { url: audioUrl } = await strategyRes.json();
    if (!audioUrl || typeof audioUrl !== 'string') {
      throw new Error('Download URL missing from storage response');
    }

    // Build webhook URL — secret goes in header, NOT in the URL
    const webhookBase = resolveWebhookBaseUrl();
    const webhookUrl  = `${webhookBase}/functions/assembly-webhook?meetingId=${encodeURIComponent(meetingId)}`;

    // Submit to AssemblyAI
    const submitRes = await fetch('https://api.assemblyai.com/v2/transcript', {
      method: 'POST',
      headers: {
        authorization: assemblyApiKey,
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        audio_url: audioUrl,
        speaker_labels: true,
        speech_models: ['universal-2'],
        webhook_url: webhookUrl,
        webhook_auth_header_name: 'x-webhook-token',
        webhook_auth_header_value: webhookSecret,
      }),
    });

    if (!submitRes.ok) {
      const detail = await submitRes.text();
      throw new Error(`AssemblyAI submit failed: ${detail}`);
    }

    const { id: transcriptId } = await submitRes.json();

    // Persist transcript ID immediately — this is the idempotency key
    await client.database
      .from('meetings')
      .update({ assembly_transcript_id: transcriptId })
      .eq('id', meetingId);

    return json(
      { success: true, meetingId, transcriptId, status: 'processing', message: 'Transcription queued' },
      202,
    );

  } catch (err) {
    const message = err instanceof Error ? err.message : 'audio-worker failed';

    // Roll back to pending so the cron can retry
    await client.database
      .from('meetings')
      .update({
        stage: 'pending',
        last_error: message,
        retry_count: 0,
      })
      .eq('id', meetingId)
      .eq('stage', 'transcribing');

    return json({ success: false, meetingId, message }, 500);
  }
}
