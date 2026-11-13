import MarkdownIt from 'markdown-it';

const repository = 'youssefsz/fitness-tracker';
const github = `https://github.com/${repository}`;
const markdown = new MarkdownIt({ html: false });
const escape = markdown.utils.escapeHtml;
const dateFormat = new Intl.DateTimeFormat('en', {
  month: 'long', day: 'numeric', year: 'numeric', timeZone: 'UTC',
});

// The notes come from GitHub. Treat raw HTML as text and omit remote images.
markdown.disable('image');
for (const rule of ['heading_open', 'heading_close']) {
  markdown.renderer.rules[rule] = (tokens, i, options, _env, self) => {
    tokens[i].tag = `h${Math.min(6, Number(tokens[i].tag[1]) + 3)}`;
    return self.renderToken(tokens, i, options);
  };
}

export async function listReleases() {
  const releases = [];
  for (let page = 1; ; page += 1) {
    const response = await fetch(
      `https://api.github.com/repos/${repository}/releases?per_page=100&page=${page}`,
      {
        headers: {
          Accept: 'application/vnd.github+json',
          'User-Agent': 'Fitness-Tracker-Website',
        },
        signal: AbortSignal.timeout(20_000),
      },
    );
    if (!response.ok) throw new Error(`GitHub Releases returned HTTP ${response.status}.`);
    releases.push(...await response.json());
    if (!response.headers.get('link')?.includes('rel="next"')) return releases;
  }
}

export function publishedApks(releases) {
  return releases.flatMap((release) => {
    const tag = release.tag_name;
    const date = new Date(release.published_at);
    if (release.draft || !/^v\d+\.\d+\.\d+(?:-[\w.-]+)?$/.test(tag) ||
        !release.published_at || Number.isNaN(date.valueOf())) return [];
    const apk = `Fitness-Tracker-${tag}.apk`;
    const assets = release.assets.filter(({ state }) => state === 'uploaded');
    const download = assets.find(({ name }) => name === apk);
    if (!download) return [];
    return [{ tag, date, apk, download, checksum: assets.some(({ name }) => name === 'SHA256SUMS.txt'),
      prerelease: release.prerelease, notes: release.body ?? '' }];
  }).sort((a, b) => b.date - a.date);
}

export function apkUrl({ tag, apk }) {
  return `${github}/releases/download/${encodeURIComponent(tag)}/${encodeURIComponent(apk)}`;
}

function apkSize(release) {
  return new Intl.NumberFormat('en', { maximumFractionDigits: 1 }).format(release.download.size / 1_000_000);
}

export function latestStable(releases) {
  return releases.find((release) => !release.prerelease);
}

export function renderHome(template, releases) {
  const latest = latestStable(releases);
  return latest ? template.replace('<!-- FITNESS_LATEST -->',
    `<p class="download-version">Latest version ${escape(latest.tag)} · ${apkSize(latest)} MB</p>`) : template;
}

function renderRelease(release, latest) {
  const { tag, date, checksum, prerelease, notes } = release;
  const assets = `${github}/releases/download/${encodeURIComponent(tag)}`;
  const heading = latest ? 'h2' : 'h3';
  return `<article class="release-entry">
    <${heading}>${latest ? 'Latest stable · ' : ''}${escape(tag)}${prerelease ? ' · Prerelease' : ''}</${heading}>
    <p><time datetime="${date.toISOString()}">${dateFormat.format(date)}</time></p>
    <div class="release-actions">
      <a${latest ? ' class="download-button"' : ''} href="${apkUrl(release)}">Download APK · ${apkSize(release)} MB</a>
      ${checksum ? `<a href="${assets}/SHA256SUMS.txt">SHA-256 checksum</a>` : ''}
      <a href="${github}/releases/tag/${encodeURIComponent(tag)}">View on GitHub</a>
    </div>
    ${notes.trim() ? `<details class="release-notes"${latest ? ' open' : ''}>
      <summary>What’s new in ${escape(tag)}</summary>
      ${markdown.render(notes)}
    </details>` : ''}
  </article>`;
}

export function renderDownloads(template, releases) {
  const latest = latestStable(releases);
  const older = releases.filter((release) => release !== latest);
  const sections = [
    latest ? renderRelease(latest, true) : '<p>No stable Android releases yet.</p>',
    older.length ? `<h2>${latest ? 'Previous versions and previews' : 'Preview releases'}</h2>` +
      older.map((release) => renderRelease(release, false)).join('\n') : '',
    `<p><a href="${github}/releases">View all releases on GitHub</a></p>`,
  ].join('\n');
  return template.replace(
    /<!-- FITNESS_RELEASES_START -->[\s\S]*?<!-- FITNESS_RELEASES_END -->/,
    () => `<section class="release-list" aria-label="Android releases">${sections}</section>`,
  );
}
