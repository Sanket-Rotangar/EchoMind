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

const meetingSchema = {
  type: 'object',
  properties: {
    bottom_line:        { type: 'string' },
    decisions_register: { type: 'array', items: { type: 'string' } },
    action_matrix: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          assignee: { type: 'string' },
          task:     { type: 'string' },
          deadline: { type: 'string', nullable: true },
        },
        required: ['assignee', 'task'],
      },
    },
    risks_and_blockers: { type: 'array', items: { type: 'string' } },
    key_metrics:        { type: 'array', items: { type: 'string' } },
  },
  required: ['bottom_line', 'decisions_register', 'action_matrix', 'risks_and_blockers', 'key_metrics'],
};

const buildPrompt = (transcriptText: string): string => `
Analyze this meeting transcript. Extract the core objective, definitive action items, and deadlines.
Do not invent data. Resolve pronouns to specific speakers.

TRANSCRIPT:
${transcriptText}
`;

const sanitizeJson = (raw: string): string => {
  const trimmed = raw.trim();
  if (!trimmed.startsWith('\`\`\`')) return trimmed;
  return trimmed
    .replace(/^\`\`\`(?:json)?\s*/i, '')
    .replace(/\s*\`\`\`$/, '')
    .trim();
};

const buildTitle = (bottomLine: string): string => {
  const line = String(bottomLine).trim();
  return line.length > 40 ? `${line.slice(0, 40)}…` : line;
};

const extractInsights = async (geminiApiKey: string, transcriptArray: string[]): Promise<Record<string, unknown>> => {
  const transcriptText = transcriptArray.join('\n');

  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${geminiApiKey}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [{ parts: [{ text: buildPrompt(transcriptText) }] }],
        generationConfig: {
          responseMimeType: 'application/json',
          responseSchema: meetingSchema,
        },
      }),
    },
  );

  if (!res.ok) {
    const detail = await res.text();
    throw new Error(`Gemini call failed: ${detail}`);
  }

  const payload = await res.json();
  const content = payload?.candidates?.[0]?.content?.parts?.[0]?.text;

  if (!content || typeof content !== 'string') {
    throw new Error('Gemini returned empty content');
  }

  return JSON.parse(sanitizeJson(content));
};

export default async function handler(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return json({ success: false, message: 'Method not allowed' }, 405);
  }

  const baseUrl      = Deno.env.get('INSFORGE_BASE_URL');
  const apiKey       = Deno.env.get('API_KEY');
  const geminiApiKey = Deno.env.get('GEMINI_API_KEY');

  if (!baseUrl || !apiKey || !geminiApiKey) {
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
    // Atomic stage claim: only advance from 'transcribed' → 'extracting'
    // Also fetches raw_transcript in the same round-trip
    const { data: claimed, error: claimError } = await client.database
      .from('meetings')
      .update({
        stage: 'extracting',
        last_attempted_at: new Date().toISOString(),
      })
      .eq('id', meetingId)
      .eq('stage', 'transcribed')
      .select('id, raw_transcript');

    if (claimError) {
      return json({ success: false, message: claimError.message }, 500);
    }

    // Another invocation already claimed this stage — safe to exit
    if (!claimed || claimed.length === 0) {
      return json({ success: true, meetingId, message: 'Stage already claimed or not ready' }, 200);
    }

    const rawTranscript = claimed[0]?.raw_transcript;

    const transcriptArray: string[] = Array.isArray(rawTranscript)
      ? rawTranscript.map(String)
      : typeof rawTranscript === 'string'
        ? [rawTranscript]
        : [];

    if (transcriptArray.length === 0) {
      // raw_transcript missing — roll back to transcribing so cron re-fetches it
      await client.database
        .from('meetings')
        .update({
          stage: 'transcribing',
          last_error: 'raw_transcript was empty at extraction stage',
        })
        .eq('id', meetingId);

      return json({ success: false, meetingId, message: 'raw_transcript is empty' }, 500);
    }

    // Call Gemini
    const insights = await extractInsights(geminiApiKey, transcriptArray);
    const title    = insights?.bottom_line ? buildTitle(String(insights.bottom_line)) : 'Untitled Meeting';

    // Atomic commit via Postgres RPC — all three DB ops in one transaction
    const { error: rpcError } = await client.database.rpc('commit_meeting_results', {
      p_meeting_id: meetingId,
      p_insights:   insights,
      p_title:      title,
    });

    if (rpcError) {
      throw new Error(`commit_meeting_results RPC failed: ${rpcError.message}`);
    }

    return json({ success: true, meetingId, message: 'Extraction complete' }, 200);

  } catch (err) {
    const message = err instanceof Error ? err.message : 'extract-intelligence failed';

    // Roll back to 'transcribed' so the cron retries only Gemini — never AssemblyAI
    await client.database
      .from('meetings')
      .update({
        stage:      'transcribed',
        last_error: message,
        retry_count: 0,
      })
      .eq('id', meetingId)
      .eq('stage', 'extracting');

    return json({ success: false, meetingId, message }, 500);
  }
}
