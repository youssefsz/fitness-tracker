import { listReleases, publishedApks } from '../releases.mjs';

const cacheSeconds = 300;

export async function releaseFeed({ request, waitUntil }) {
  const key = new Request(new URL('/.fitness-release-feed', request.url));
  const cached = await caches.default.match(key);
  const items = cached ? await cached.json() : await listReleases();
  if (!cached) {
    const response = Response.json(items, {
      headers: { 'Cache-Control': `public, max-age=${cacheSeconds}` },
    });
    waitUntil(caches.default.put(key, response));
  }
  return publishedApks(items);
}

export function releasePage(render) {
  return async function onRequestGet(context) {
    const { request, env } = context;
    const url = new URL(request.url);
    url.search = '';
    const response = await env.ASSETS.fetch(new Request(url));
    if (!response.ok) return response;
    const template = await response.text();
    const headers = new Headers(response.headers);
    for (const name of ['content-length', 'content-encoding', 'etag', 'last-modified']) {
      headers.delete(name);
    }
    // A single cached feed keeps the homepage label and download destination in sync.
    headers.set('Cache-Control', 'no-store');
    try {
      return new Response(render(template, await releaseFeed(context)), { headers });
    } catch (error) {
      console.error('GitHub release list unavailable:', error.message);
      return new Response(template.replace(
        '<p>No Android releases yet.</p>',
        '<p>The release list is temporarily unavailable. Open GitHub for downloads.</p>',
      ), { headers });
    }
  };
}
