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

  if (!baseUrl || !apiKey) {
    return json({ success: false, message: 'Server configuration error' }, 500);
  }

  try {
    const randomPart = crypto.randomUUID().replace(/-/g, '').slice(0, 8);
    const path = `${Date.now()}-${randomPart}`;

    const uploadStrategyResponse = await fetch(
      `${baseUrl}/api/storage/buckets/meetings/upload-strategy`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          filename: path,
          contentType: 'audio/mp4',
        }),
      },
    );

    const strategy = await uploadStrategyResponse.json();

    if (!uploadStrategyResponse.ok) {
      return json({ success: false, message: 'Failed to generate upload URL' }, 500);
    }

    const uploadUrl =
      typeof strategy.uploadUrl === 'string' && strategy.uploadUrl.startsWith('http')
        ? strategy.uploadUrl
        : `${baseUrl}${strategy.uploadUrl}`;

    return json({
      success: true,
      uploadUrl,
      path: strategy.key || path,
      method: strategy.method,
      fields: strategy.fields || null,
      confirmRequired: strategy.confirmRequired || false,
      confirmUrl: strategy.confirmUrl || null,
      expiresAt: strategy.expiresAt || null,
    });
  } catch (_error) {
    return json({ success: false, message: 'Failed to generate upload URL' }, 500);
  }
}
