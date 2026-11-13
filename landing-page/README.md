# Fitness Tracker website

Run these commands from the repository root with Node.js 22 or newer:

```sh
npm --prefix landing-page ci
npm --prefix landing-page run build
python3 -m http.server 5501 --directory landing-page/dist
```

Open http://localhost:5501 to preview the static pages. Set `FITNESS_RELEASE_FIXTURE` to a JSON file shaped like the GitHub Releases API response to preview populated downloads locally.

Cloudflare Pages uses `landing-page` as the root, `npm run build` as the build command, and `dist` as the output directory. The production branch is `main`, previews are disabled, and the build watch include pattern is `landing-page/*`. The project serves `fitness-tracker.dhibi.tn`.

The Downloads Pages Function reads published release metadata from GitHub and caches the rendered page for five minutes. A release refreshes the download list without a site deployment. GitHub serves the APKs and checksums.
