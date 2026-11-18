# Fitness Tracker website

Run these commands from the repository root with Node.js 22 or newer:

```sh
npm --prefix landing-page ci
npm --prefix landing-page test
npm --prefix landing-page run build
python3 -m http.server 5501 --directory landing-page/dist
```

Open http://localhost:5501 to preview the static pages. The build fetches published GitHub releases once and requires at least one stable release with an uploaded APK. Set `GITHUB_TOKEN` in your shell for authenticated reads. Local builds can read the public API without a token.

For an offline preview, set `FITNESS_RELEASE_FIXTURE` to an absolute path to a JSON file shaped like the GitHub Releases API response. Include a stable release with its uploaded APK and a positive asset size. Fixtures are rejected in Cloudflare builds.

The host tests build the site with fictional release records. They cover pagination, authentication, download destinations, successive releases, and failed reads preserving an existing build. Website CI runs them on website changes.

## Configure Cloudflare Pages

The project serves `fitness-tracker.dhibi.tn`. Keep these build settings:

| Setting | Value |
| --- | --- |
| Root directory | `landing-page` |
| Build command | `npm run build` |
| Output directory | `dist` |
| Production branch | `main` |
| Preview deployments | Disabled |
| Build watch include pattern | `landing-page/*` |
| Node.js version | 22 or newer |

Add `GITHUB_TOKEN` as a secret in the production build environment. Use a GitHub token restricted to this repository with read-only Contents permission. The token is only used during the build and is never written to the site. Cloudflare builds fail if the token is missing.

Create a [Cloudflare Pages deploy hook](https://developers.cloudflare.com/pages/configuration/deploy-hooks/) for `main`. Save its URL as the GitHub Actions repository secret `CLOUDFLARE_PAGES_DEPLOY_HOOK`. Treat the URL as a credential.

Configure both secrets before deploying this change or publishing the next Android release. The website uses static files and Cloudflare redirects. It no longer deploys Pages Functions or queries GitHub when someone visits.

## Refresh downloads after a release

The Android release workflow calls the deploy hook after publishing the APK, checksum, and update metadata. This step also runs when the workflow finds an already completed release. It calls the hook directly because releases published with `GITHUB_TOKEN` do not trigger release-event workflows.

The hook starts a build of `main`. The homepage version, direct APK links, Downloads page, and `/download` and `/download/` redirects are generated from the same release list. GitHub continues to host the APKs and checksums.

If GitHub is unavailable, authentication fails, or no stable APK is found, the build fails. Cloudflare keeps serving the previous successful deployment. A failed refresh never publishes an empty release list.

A successful hook request means Cloudflare accepted the deployment trigger. Check the Pages deployment result to confirm the new version is live. If the hook step fails, the GitHub release stays published. Rerun the failed publish job to retry the hook without replacing the release assets. For a failed Cloudflare build, fix the reported error and retry that deployment. For a manually published or edited release, invoke the deploy hook or retry the latest production deployment in Pages.

The Python preview server uses the generated download fallback page. To test Cloudflare's HTTP 302 redirects locally, run `npx wrangler pages dev landing-page/dist` from the repository root.
