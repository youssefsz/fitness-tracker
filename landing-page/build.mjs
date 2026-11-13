import { cp, mkdir, readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { publishedApks, renderDownloads, renderHome } from './releases.mjs';

const site = fileURLToPath(new URL('./', import.meta.url));
const output = resolve(site, 'dist');
const fixture = process.env.FITNESS_RELEASE_FIXTURE;

await mkdir(output, { recursive: true });
for (const path of ['index.html', '404.html', 'script.js', 'styles.css', 'phone-frame.css', 'robots.txt',
  'sitemap.xml', '_routes.json', '_headers', 'assets', 'download', 'downloads', 'docs', 'privacy', 'terms']) {
  await cp(resolve(site, path), resolve(output, path), { recursive: true });
}
if (fixture) {
  const releases = publishedApks(JSON.parse(await readFile(fixture, 'utf8')));
  for (const [path, render] of [['index.html', renderHome], ['downloads/index.html', renderDownloads]]) {
    const template = await readFile(resolve(site, path), 'utf8');
    await writeFile(resolve(output, path), render(template, releases));
  }
}
console.log('Built the Fitness Tracker website.');
