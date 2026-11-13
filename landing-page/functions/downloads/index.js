import { renderDownloads } from '../../releases.mjs';
import { releasePage } from '../../runtime/release-feed.mjs';

const downloadsPage = releasePage(renderDownloads);

export function onRequestGet(context) {
  const url = new URL(context.request.url);
  if (url.pathname === '/downloads') return Response.redirect(new URL('/downloads/', url.origin), 308);
  return downloadsPage(context);
}
