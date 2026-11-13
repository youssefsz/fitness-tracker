import { apkUrl, listReleases, publishedApks } from '../releases.mjs';

export async function onRequestGet({ request, waitUntil }) {
  const key = new Request(new URL('/download', request.url));
  const cached = await caches.default.match(key);
  if (cached) return cached;

  const fallback = new URL('/downloads/', key.url);
  try {
    const latest = publishedApks(await listReleases()).find((release) => !release.prerelease);
    const redirect = new Response(null, {
      status: 302,
      headers: {
        Location: latest ? apkUrl(latest) : fallback.href,
        'Cache-Control': 'public, max-age=300',
      },
    });
    waitUntil(caches.default.put(key, redirect.clone()));
    return redirect;
  } catch (error) {
    console.error('Latest APK lookup failed:', error.message);
    return new Response(null, {
      status: 302,
      headers: { Location: fallback.href, 'Cache-Control': 'no-store' },
    });
  }
}
