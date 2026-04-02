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

const MAX_RETRIES   = 3;
const STALE_MINUTES = 5;

export default async function handler(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return json({ success: false, message: 'Method not allowed' }, 405);
  }

  const baseUrl = Deno.env.get('INSFORGE_BASE_URL');
  const apiKey  = Deno.env.get('API_KEY');

  if (!baseUrl || !apiKey) {
    return json({ success: false, message: 'Server configuration error' }, 500);
  }

  const client      = createClient({ baseUrl, edgeFunctionToken: apiKey });
  const stalecutoff = new Date(Date.now() - STALE_MINUTES * 60 * 1000).toISOString();

  const results = {
    scanned:            0,
    transcriptionRetry: 0,
    extractionRetry:    0,
    markedFailed:       0,
    errors:             [] as string[],
  };

  try {
    // -------------------------------------------------------------------------
    // BUCKET 1: Stuck at 'pending' or 'transcribing' without an AssemblyAI ID
    // Cause: audio-worker was called but failed before submitting to AssemblyAI
    // Fix:   increment retry_count and re-kick audio-worker
    // -------------------------------------------------------------------------
    const { data: transcriptionStuck, error: err1 } = await client.database
      .from('meetings')
      .select('id, retry_count')
      .in('stage', ['pending', 'transcribing'])
      .is('assembly_transcript_id', null)
      .lt('retry_count', MAX_RETRIES)
      .lt('last_attempted_at', stalecutoff)
      .order('created_at', { ascending: true })
      .limit(20);

    if (err1) throw new Error(`Bucket1 query failed: ${err1.message}`);

    for (const m of (transcriptionStuck ?? [])) {
      results.scanned++;
      const nextRetry = (m.retry_count ?? 0) + 1;

      if (nextRetry > MAX_RETRIES) {
        const { error: failErr } = await client.database
          .from('meetings')
          .update({ status: 'failed', stage: 'failed', last_error: 'Max retries exceeded at transcription stage' })
          .eq('id', m.id)
          .in('stage', ['pending', 'transcribing']);

        if (!failErr) results.markedFailed++;
        continue;
      }

      // Optimistic increment — prevents double-retry if cron fires twice
      const { data: incremented, error: incErr } = await client.database
        .from('meetings')
        .update({ retry_count: nextRetry, stage: 'pending' })
        .eq('id', m.id)
        .eq('retry_count', m.retry_count) // only update if count hasn't changed
        .select('id');

      if (incErr || !incremented || incremented.length === 0) continue;

      fetch(`${baseUrl}/functions/audio-worker`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ meetingId: m.id }),
      }).catch(() => {});

      results.transcriptionRetry++;
    }

    // -------------------------------------------------------------------------
    // BUCKET 2: Stuck at 'transcribed' — raw transcript saved, Gemini never ran
    // Cause: extract-intelligence call failed or was never made
    // Fix:   re-kick extract-intelligence only — AssemblyAI is never called again
    // -------------------------------------------------------------------------
    const { data: extractionStuck, error: err2 } = await client.database
      .from('meetings')
      .select('id, retry_count')
      .eq('stage', 'transcribed')
      .not('raw_transcript', 'is', null)
      .lt('retry_count', MAX_RETRIES)
      .lt('last_attempted_at', stalecutoff)
      .order('created_at', { ascending: true })
      .limit(20);

    if (err2) throw new Error(`Bucket2 query failed: ${err2.message}`);

    for (const m of (extractionStuck ?? [])) {
      results.scanned++;
      const nextRetry = (m.retry_count ?? 0) + 1;

      if (nextRetry > MAX_RETRIES) {
        const { error: failErr } = await client.database
          .from('meetings')
          .update({ status: 'failed', stage: 'failed', last_error: 'Max retries exceeded at extraction stage' })
          .eq('id', m.id)
          .eq('stage', 'transcribed');

        if (!failErr) results.markedFailed++;
        continue;
      }

      // Optimistic increment
      const { data: incremented, error: incErr } = await client.database
        .from('meetings')
        .update({ retry_count: nextRetry })
        .eq('id', m.id)
        .eq('retry_count', m.retry_count)
        .select('id');

      if (incErr || !incremented || incremented.length === 0) continue;

      fetch(`${baseUrl}/functions/extract-intelligence`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ meetingId: m.id }),
      }).catch(() => {});

      results.extractionRetry++;
    }

    // -------------------------------------------------------------------------
    // BUCKET 3: Hard failures — exceeded retries, mark as failed
    // Catches anything that slipped through the per-bucket retry guards above
    // -------------------------------------------------------------------------
    const { data: exceeded, error: err3 } = await client.database
      .from('meetings')
      .select('id')
      .in('stage', ['pending', 'transcribing', 'transcribed', 'extracting'])
      .gte('retry_count', MAX_RETRIES)
      .lt('last_attempted_at', stalecutoff);

    if (err3) throw new Error(`Bucket3 query failed: ${err3.message}`);

    for (const m of (exceeded ?? [])) {
      const { error: failErr } = await client.database
        .from('meetings')
        .update({ status: 'failed', stage: 'failed', last_error: 'Max retries exceeded' })
        .eq('id', m.id)
        .not('stage', 'in', '("completed","failed")');

      if (!failErr) results.markedFailed++;
    }

    return json({ success: true, ...results }, 200);

  } catch (err) {
    const message = err instanceof Error ? err.message : 'cron failed';
    return json({ success: false, message, ...results }, 500);
  }
}
