import { apkUrl, latestStable } from '../releases.mjs';
import { releaseFeed } from '../runtime/release-feed.mjs';

export async function onRequestGet(context) {
  const fallback = new URL('/downloads/', context.request.url);
  let destination = fallback.href;
  try {
    const latest = latestStable(await releaseFeed(context));
    if (latest) destination = apkUrl(latest);
  } catch (error) {
    console.error('Latest APK lookup failed:', error.message);
  }
  return new Response(null, {
    status: 302,
    headers: { Location: destination, 'Cache-Control': 'no-store' },
  });
}
