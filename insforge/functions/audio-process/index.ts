import { createClient } from 'npm:@insforge/sdk';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization, x-user-id',
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

  const baseUrl = Deno.env.get('INSFORGE_BASE_URL');
  const apiKey  = Deno.env.get('API_KEY');
  const userId  = req.headers.get('x-user-id') ?? req.headers.get('user-id');

  if (!baseUrl || !apiKey) {
    return json({ success: false, message: 'Server configuration error' }, 500);
  }

  if (!userId) {
    return json({ success: false, message: 'x-user-id header is required' }, 400);
  }

  let path: string;
  try {
    const body = await req.json();
    path = typeof body?.path === 'string' ? body.path.trim() : '';
  } catch {
    return json({ success: false, message: 'Invalid JSON body' }, 400);
  }

  if (!path) {
    return json({ success: false, message: 'path is required' }, 400);
  }

  const client = createClient({ baseUrl, edgeFunctionToken: apiKey });

  // Check if a meeting for this user+path already exists (idempotency)
  const { data: existing, error: lookupError } = await client.database
    .from('meetings')
    .select('id, status, stage')
    .eq('user_id', userId)
    .eq('audio_storage_path', path)
    .maybeSingle();

  if (lookupError) {
    return json({ success: false, message: lookupError.message }, 500);
  }

  if (existing) {
    // Already exists — kick the worker in case it stalled, then return existing id
    fetch(`${baseUrl}/functions/audio-worker`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ meetingId: existing.id }),
    }).catch(() => {/* fire and forget */});

    return json(
      {
        success: true,
        meetingId: existing.id,
        message: 'Meeting already exists. Worker nudged.',
      },
      200,
    );
  }

  // Create new meeting row — stage starts at 'pending'
  const { data: meeting, error: createError } = await client.database
    .from('meetings')
    .insert([
      {
        user_id: userId,
        title: 'Processing Meeting...',
        status: 'processing',
        stage: 'pending',
        audio_storage_path: path,
        retry_count: 0,
      },
    ])
    .select('id')
    .single();

  if (createError || !meeting?.id) {
    return json(
      { success: false, message: createError?.message ?? 'Failed to create meeting' },
      500,
    );
  }

  // Fire-and-forget: kick the worker immediately
  fetch(`${baseUrl}/functions/audio-worker`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ meetingId: meeting.id }),
  }).catch(() => {/* cron will retry if this fails */});

  return json(
    {
      success: true,
      meetingId: meeting.id,
      message: 'Audio received. Processing in background.',
    },
    202,
  );
}
