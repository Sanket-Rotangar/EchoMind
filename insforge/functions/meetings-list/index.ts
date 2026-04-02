import { createClient } from 'npm:@insforge/sdk';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
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

  if (req.method !== 'GET') {
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
    const limit = Number.parseInt(url.searchParams.get('limit') ?? '8', 10);
    const offset = Number.parseInt(url.searchParams.get('offset') ?? '0', 10);

    const safeLimit = Number.isFinite(limit) && limit > 0 ? limit : 8;
    const safeOffset = Number.isFinite(offset) && offset >= 0 ? offset : 0;

    const client = createClient({
      baseUrl,
      edgeFunctionToken: apiKey,
    });

    const { data, error } = await client.database
      .from('meetings')
      .select('id, title, status, created_at')
      .eq('user_id', userId)
      .order('created_at', { ascending: false })
      .range(safeOffset, safeOffset + safeLimit - 1);

    if (error) {
      return json({ success: false, message: error.message || 'Failed to fetch meetings' }, 500);
    }

    return json({ success: true, data: data ?? [] }, 200);
  } catch (error) {
    return json({ success: false, message: error instanceof Error ? error.message : 'Failed to fetch meetings' }, 500);
  }
}
