import { cp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { apkUrl, latestStable, listReleases, publishedApks, renderDownloads, renderHome } from './releases.mjs';

const site = fileURLToPath(new URL('./', import.meta.url));

export async function buildSite({
  output = resolve(site, 'dist'),
  fixture = process.env.FITNESS_RELEASE_FIXTURE,
  token = process.env.GITHUB_TOKEN,
} = {}) {
  if (process.env.CF_PAGES === '1') {
    if (fixture) throw new Error('Release fixtures are only supported for local previews.');
    if (!token) throw new Error('Set the GITHUB_TOKEN build secret in Cloudflare Pages.');
  }
  // Validate before touching the output. A failed build must not publish an empty list.
  const items = fixture ? JSON.parse(await readFile(fixture, 'utf8')) : await listReleases({ token });
  const releases = publishedApks(items);
  const latest = latestStable(releases);
  if (!latest) throw new Error('No published stable Android APK found. Keeping the previous deployment.');
  const destination = apkUrl(latest);

  await rm(output, { recursive: true, force: true });
  await mkdir(output, { recursive: true });
  for (const path of ['index.html', '404.html', 'script.js', 'styles.css', 'phone-frame.css', 'robots.txt',
    'sitemap.xml', '_headers', 'assets', 'download', 'downloads', 'docs', 'privacy', 'terms']) {
    await cp(resolve(site, path), resolve(output, path), { recursive: true });
  }
  const assets = await Promise.all(['styles.css', 'phone-frame.css', 'script.js'].map(async (path) => {
    const content = await readFile(resolve(site, path));
    const hash = createHash('sha256').update(content).digest('hex').slice(0, 12);
    const versioned = path.replace(/\.(css|js)$/, `.${hash}.$1`);
    await writeFile(resolve(output, versioned), content);
    return [path, versioned];
  }));
  for (const path of ['index.html', '404.html', 'downloads/index.html', 'docs/index.html',
    'privacy/index.html', 'terms/index.html']) {
    const target = resolve(output, path);
    let html = await readFile(target, 'utf8');
    for (const [asset, versioned] of assets) {
      html = html.replaceAll(`${asset}"`, `${versioned}"`);
    }
    await writeFile(target, html);
  }
  for (const [path, render] of [['index.html', renderHome], ['downloads/index.html', renderDownloads]]) {
    const template = await readFile(resolve(output, path), 'utf8');
    await writeFile(resolve(output, path), render(template, releases));
  }
  const download = resolve(output, 'download/index.html');
  await writeFile(download, (await readFile(download, 'utf8')).replaceAll('/downloads/', destination));
  await writeFile(resolve(output, '_redirects'),
    `/download ${destination} 302\n/download/ ${destination} 302\n`);
  console.log(`Built the Fitness Tracker website with ${releases.length} releases. Latest stable: ${latest.tag}.`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await buildSite();
}
