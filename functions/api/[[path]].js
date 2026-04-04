const HOP_BY_HOP_HEADERS = new Set([
  'connection',
  'keep-alive',
  'proxy-authenticate',
  'proxy-authorization',
  'te',
  'trailers',
  'transfer-encoding',
  'upgrade',
]);

function normalizeOrigin(origin) {
  return origin.endsWith('/') ? origin.slice(0, -1) : origin;
}

export async function onRequest(context) {
  const apiOrigin = context.env.MAYBEFLAT_API_ORIGIN;
  if (!apiOrigin) {
    return new Response(
      'Missing MAYBEFLAT_API_ORIGIN Pages environment variable.',
      { status: 500 },
    );
  }

  const requestUrl = new URL(context.request.url);
  const upstreamUrl = new URL(
    normalizeOrigin(apiOrigin) +
      (requestUrl.pathname.replace(/^\/api(?=\/|$)/, '') || '/'),
  );
  upstreamUrl.search = requestUrl.search;

  const headers = new Headers(context.request.headers);
  for (const header of HOP_BY_HOP_HEADERS) {
    headers.delete(header);
  }
  headers.delete('host');

  const init = {
    method: context.request.method,
    headers,
    redirect: 'manual',
  };
  if (
    context.request.method !== 'GET' &&
    context.request.method !== 'HEAD'
  ) {
    init.body = context.request.body;
  }

  try {
    const upstreamResponse = await fetch(upstreamUrl, init);
    const responseHeaders = new Headers(upstreamResponse.headers);
    responseHeaders.delete('content-length');
    return new Response(upstreamResponse.body, {
      status: upstreamResponse.status,
      statusText: upstreamResponse.statusText,
      headers: responseHeaders,
    });
  } catch (error) {
    return new Response(
      `Maybeflat API proxy failed: ${error instanceof Error ? error.message : 'unknown error'}`,
      { status: 502 },
    );
  }
}
