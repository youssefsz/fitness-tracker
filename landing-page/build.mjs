import { cp, mkdir, readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { renderDownloads } from './releases.mjs';

const site = fileURLToPath(new URL('./', import.meta.url));
const output = resolve(site, 'dist');
const template = await readFile(resolve(site, 'downloads/index.html'), 'utf8');
const fixture = process.env.FITNESS_RELEASE_FIXTURE;
const releases = fixture ? JSON.parse(await readFile(fixture, 'utf8')) : [];
const page = fixture ? renderDownloads(template, releases) : template;

await mkdir(output, { recursive: true });
for (const path of ['index.html', '404.html', 'script.js', 'styles.css', 'phone-frame.css', 'robots.txt',
  'sitemap.xml', '_routes.json', '_headers', 'assets', 'download', 'downloads', 'docs', 'privacy', 'terms']) {
  await cp(resolve(site, path), resolve(output, path), { recursive: true });
}
await writeFile(resolve(output, 'downloads/index.html'), page);
console.log('Built the Fitness Tracker website.');
