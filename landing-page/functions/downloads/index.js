import { listReleases, renderDownloads } from '../../releases.mjs';

export async function onRequestGet({ request, env, waitUntil }) {
  // Cache by site origin and path. A query string does not change the release list.
  const url = new URL(request.url);
  if (url.pathname === '/downloads') return Response.redirect(new URL('/downloads/', url.origin), 308);
  const cacheKey = new Request(new URL('/downloads/', url.origin));
  const cache = caches.default;
  const cached = await cache.match(cacheKey);
  if (cached) return cached;

  const templateUrl = new URL('/downloads/', url.origin);
  const response = await env.ASSETS.fetch(new Request(templateUrl));
  if (!response.ok) return response;
  const template = await response.text();

  try {
    const releases = await listReleases();
    const page = new Response(renderDownloads(template, releases), {
      headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'public, max-age=300' },
    });
    waitUntil(cache.put(cacheKey, page.clone()));
    return page;
  } catch (error) {
    console.error('GitHub release list unavailable:', error.message);
    return new Response(template.replace(
      '<p>No Android releases yet.</p>',
      '<p>The release list is temporarily unavailable. Open GitHub for downloads.</p>',
    ), {
      headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' },
    });
  }
}
