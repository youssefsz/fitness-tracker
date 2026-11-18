import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { buildSite } from '../build.mjs';
import { listReleases } from '../releases.mjs';

function release(tag, { prerelease = false, date = '2026-01-02T12:00:00Z' } = {}) {
  return {
    tag_name: tag, published_at: date, draft: false, prerelease,
    body: '## Changes\n\nFictional release notes.\n\n<script>alert(1)</script>\n\n![Remote image](https://example.com/image.png)\n\n[Unsafe link](javascript:alert(1))',
    assets: [
      { name: `Fitness-Tracker-${tag}.apk`, state: 'uploaded', size: 12_500_000 },
      { name: 'SHA256SUMS.txt', state: 'uploaded', size: 100 },
    ],
  };
}

const stable = release('v2.0.0');
const releases = [
  release('v2.1.0-beta.1', { prerelease: true, date: '2026-01-03T12:00:00Z' }),
  stable,
  release('v1.9.0', { date: '2026-01-01T12:00:00Z' }),
  { ...release('v3.0.0'), draft: true, body: 'Unpublished draft notes must stay private.' },
];
const apk = 'https://github.com/youssefsz/fitness-tracker/releases/download/v2.0.0/Fitness-Tracker-v2.0.0.apk';

async function temporaryOutput(t) {
  const directory = await mkdtemp(join(tmpdir(), 'fitness-website-test-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  return join(directory, 'dist');
}

async function readOutput(output) {
  return Promise.all(['index.html', 'downloads/index.html', 'download/index.html', '_redirects']
    .map((path) => readFile(join(output, path), 'utf8')));
}

async function outputFiles(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = await Promise.all(entries.map((entry) => {
    const path = join(directory, entry.name);
    return entry.isDirectory() ? outputFiles(path) : [path];
  }));
  return files.flat();
}

test('fetches every release page with authentication', async (t) => {
  const requests = [];
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    requests.push({ url, options });
    return requests.length === 1
      ? Response.json([stable], { headers: { Link: '<https://api.github.com/repos/youssefsz/fitness-tracker/releases?per_page=100&page=2>; rel="next"' } })
      : Response.json([releases[2]]);
  });
  assert.deepEqual(await listReleases({ token: 'test-only-token' }), [stable, releases[2]]);
  assert.equal(requests.length, 2);
  assert.match(requests[1].url, /page=2$/);
  for (const { options } of requests) {
    assert.equal(options.headers.Authorization, 'Bearer test-only-token');
    assert.equal(options.headers['User-Agent'], 'Fitness-Tracker-Website');
    assert.ok(options.signal instanceof AbortSignal);
  }
});

test('does not return partial releases when a later page fails', async (t) => {
  let calls = 0;
  t.mock.method(globalThis, 'fetch', async () => ++calls === 1
    ? Response.json([stable], { headers: { Link: '<https://api.github.com/repos/youssefsz/fitness-tracker/releases?page=2>; rel="next"' } })
    : new Response('', { status: 500 }));
  await assert.rejects(listReleases(), /HTTP 500/);
});

test('builds matching static download links and removes old output', async (t) => {
  const output = await temporaryOutput(t);
  t.mock.method(globalThis, 'fetch', async () => Response.json(releases));
  await buildSite({ output, fixture: null, token: 'test-only-token' });
  const [home, downloads, fallback, redirects] = await readOutput(output);
  assert.ok(home.includes(`href="${apk}"`));
  assert.match(home, /Latest version v2\.0\.0 · 12\.5 MB/);
  assert.match(downloads, /Latest stable · v2\.0\.0/);
  assert.match(downloads, /v2\.1\.0-beta\.1 · Prerelease/);
  assert.match(downloads, /v1\.9\.0/);
  assert.ok(downloads.includes(`href="${apk}"`));
  assert.match(downloads, /<h5>Changes<\/h5>/);
  assert.doesNotMatch(downloads, /<script>alert|<img/);
  assert.doesNotMatch(downloads, /href="(?:javascript|data|vbscript):/i);
  assert.doesNotMatch(downloads, /v3\.0\.0|Unpublished draft notes/);
  assert.doesNotMatch(downloads, /No .*releases|temporarily unavailable/);
  assert.ok(fallback.includes(`content="0; url=${apk}"`));
  assert.ok(fallback.includes(`href="${apk}"`));
  assert.equal(redirects, `/download ${apk} 302\n/download/ ${apk} 302\n`);
  for (const html of [home, downloads, fallback]) {
    assert.doesNotMatch(html, /test-only-token|api\.github\.com/);
  }
  assert.match(home, /script\.[a-f0-9]{12}\.js/);

  await writeFile(join(output, '_worker.js'), 'stale runtime worker');
  await writeFile(join(output, '_routes.json'), 'stale function routes');
  await writeFile(join(output, 'styles.old.css'), 'stale asset');
  const next = release('v2.1.0', { date: '2026-01-04T12:00:00Z' });
  t.mock.method(globalThis, 'fetch', async () => Response.json([next, ...releases]));
  await buildSite({ output, fixture: null, token: 'test-only-token' });
  const [newHome, , newFallback, newRedirects] = await readOutput(output);
  for (const html of [newHome, newFallback, newRedirects]) {
    assert.match(html, /releases\/download\/v2\.1\.0\/Fitness-Tracker-v2\.1\.0\.apk/);
    assert.doesNotMatch(html, /releases\/download\/v2\.0\.0\//);
  }
  const files = await readdir(output);
  for (const path of ['_worker.js', '_routes.json', 'styles.old.css', 'functions']) {
    assert.ok(!files.includes(path), `${path} must not survive a static build`);
  }
});

test('no generated file exposes build credentials or server source', async (t) => {
  const output = await temporaryOutput(t);
  const token = 'fictional-build-token-must-never-be-published';
  const hook = 'https://api.cloudflare.com/client/v4/pages/webhooks/deploy_hooks/fictional-secret';
  const previousHook = process.env.CLOUDFLARE_PAGES_DEPLOY_HOOK;
  process.env.CLOUDFLARE_PAGES_DEPLOY_HOOK = hook;
  t.after(() => {
    if (previousHook === undefined) delete process.env.CLOUDFLARE_PAGES_DEPLOY_HOOK;
    else process.env.CLOUDFLARE_PAGES_DEPLOY_HOOK = previousHook;
  });
  t.mock.method(globalThis, 'fetch', async () => Response.json(releases));
  await buildSite({ output, fixture: null, token });
  for (const path of await outputFiles(output)) {
    const content = await readFile(path);
    for (const secret of [token, hook, 'GITHUB_TOKEN', 'CLOUDFLARE_PAGES_DEPLOY_HOOK']) {
      assert.ok(!content.includes(secret), `Build credential leaked into ${path}`);
    }
    assert.ok(!path.endsWith('.mjs'), `Server source included in ${path}`);
  }
});

test('failed or unusable release reads preserve the previous build', async (t) => {
  const output = await temporaryOutput(t);
  t.mock.method(globalThis, 'fetch', async () => Response.json(releases));
  await buildSite({ output, fixture: null });
  const previous = await readOutput(output);
  const failures = [
    ['rate limit', () => new Response('', { status: 403 }), /HTTP 403/],
    ['secondary rate limit', () => new Response('', { status: 429 }), /HTTP 429/],
    ['GitHub outage', () => new Response('', { status: 503 }), /HTTP 503/],
    ['timeout', () => { throw new DOMException('Request timed out', 'TimeoutError'); }, /timed out/],
    ['invalid JSON', () => new Response('{broken'), /JSON/],
    ['invalid response shape', () => Response.json({ message: 'unexpected' }), /release list/],
    ['empty feed', () => Response.json([]), /No published stable Android APK/],
    ['preview only', () => Response.json([releases[0]]), /No published stable Android APK/],
    ['missing APK', () => Response.json([{ ...stable, assets: [] }]), /No published stable Android APK/],
    ['invalid APK size', () => Response.json([{ ...stable, assets: [{ ...stable.assets[0], size: 0 }] }]), /Invalid APK size/],
  ];
  for (const [name, response, error] of failures) {
    await t.test(name, async (t) => {
      t.mock.method(globalThis, 'fetch', async () => response());
      await assert.rejects(buildSite({ output, fixture: null }), error);
      assert.deepEqual(await readOutput(output), previous);
    });
  }
});

test('local fixtures build without contacting GitHub', async (t) => {
  const output = await temporaryOutput(t);
  const fixture = join(output, '..', 'releases.json');
  await writeFile(fixture, JSON.stringify(releases));
  t.mock.method(globalThis, 'fetch', () => { throw new Error('Unexpected network request'); });
  await buildSite({ output, fixture });
  assert.match((await readOutput(output))[0], /Latest version v2\.0\.0/);
});

test('Cloudflare builds require authentication and reject local fixtures', () => {
  for (const [token, fixture, message] of [
    ['', '', /Set the GITHUB_TOKEN build secret/],
    ['test-only-token', 'fictional.json', /fixtures are only supported for local previews/],
  ]) {
    const result = spawnSync(process.execPath, [fileURLToPath(new URL('../build.mjs', import.meta.url))], {
      encoding: 'utf8',
      env: { ...process.env, CF_PAGES: '1', GITHUB_TOKEN: token, FITNESS_RELEASE_FIXTURE: fixture },
    });
    assert.equal(result.status, 1);
    assert.match(result.stderr, message);
    assert.doesNotMatch(result.stderr, /test-only-token/);
  }
});
