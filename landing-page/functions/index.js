import { renderHome } from '../releases.mjs';
import { releasePage } from '../runtime/release-feed.mjs';

export const onRequestGet = releasePage(renderHome);
