import { createClient } from 'npm:@insforge/sdk';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
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

  if (req.method !== 'GET' && req.method !== 'POST') {
    return json({ success: false, message: 'Method not allowed' }, 405);
  }

  const baseUrl = Deno.env.get('INSFORGE_BASE_URL');
  const apiKey = Deno.env.get('API_KEY');
  const userId = req.headers.get('x-user-id') || req.headers.get('user-id');

  if (!baseUrl || !apiKey || !userId) {
    return json({ success: false, message: 'Server configuration error' }, 500);
  }

  try {
    const url = new URL(req.url);
    let bodyId: string | null = null;

    try {
      const contentType = req.headers.get('content-type') || '';
      if (contentType.includes('application/json')) {
        const payload = await req.json();
        bodyId = typeof payload?.id === 'string' ? payload.id : null;
      }
    } catch {
      bodyId = null;
    }

    const meetingId =
      url.searchParams.get('id') ||
      req.headers.get('x-meeting-id') ||
      req.headers.get('meeting-id') ||
      bodyId;

    if (!meetingId) {
      return json({ success: false, message: 'Meeting id is required' }, 400);
    }

    const client = createClient({
      baseUrl,
      edgeFunctionToken: apiKey,
    });

    const { data, error } = await client.database
      .from('meetings')
      .select('*, action_items (*)')
      .eq('id', meetingId)
      .eq('user_id', userId)
      .single();

    if (error) {
      return json({ success: false, message: error.message || 'Failed to fetch meeting' }, 500);
    }

    return json({ success: true, data }, 200);
  } catch (error) {
    return json({ success: false, message: error instanceof Error ? error.message : 'Failed to fetch meeting' }, 500);
  }
}
