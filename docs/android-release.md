# Release an Android APK

The Android release workflow builds one installable APK for the architectures supported by Flutter. It checks the tagged source and the APK signature before publishing the APK, its SHA-256 checksum, and update metadata on GitHub. Release downloads follow the repository's visibility.

## Back up the signing key

Keep an encrypted backup of the PKCS#12 keystore and save its password in your password manager. Use the same signing key for every release so Android can update existing installations. The key alias is `fitness-tracker`. [Android app signing](https://developer.android.com/studio/publish/app-signing)

The [certificate fingerprint](../android/release-signing.sha256) is public. The workflow compares it with the certificate in the finished APK. Keep the private keystore and password outside the repository.

## Configure GitHub once

In your repository settings, open **Secrets and variables → Actions** and create these repository secrets:

| Secret | Value |
| --- | --- |
| `ANDROID_RELEASE_KEYSTORE_BASE64` | The PKCS#12 keystore encoded as Base64 |
| `ANDROID_RELEASE_PASSWORD` | The keystore password |
| `CLOUDFLARE_PAGES_DEPLOY_HOOK` | The production website deploy-hook URL, configured in the [website setup](../landing-page/README.md#configure-cloudflare-pages) |

With the GitHub CLI, you can pipe secrets into `gh secret set NAME --repo OWNER/REPO` instead of copying them through the clipboard. Base64 represents binary data as text. Treat the encoded keystore as private. [GitHub Actions secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets)

## Build a signed APK locally

Set `ANDROID_RELEASE_KEYSTORE` to the absolute path of the keystore. Load `ANDROID_RELEASE_PASSWORD` from your password manager or credential store into the environment of the build. Run these commands from the repository root:

```text
flutter pub get --enforce-lockfile
flutter build apk --release
```

Find the APK at `build/app/outputs/flutter-apk/app-release.apk`. Use `apksigner verify --verbose --print-certs` from Android SDK Build Tools to verify it and compare the certificate's SHA-256 digest with the repository fingerprint. Debug builds use the standard Android debug key and require no release credentials.

## Publish a version

1. Update the version and increase the build number in [pubspec.yaml](../pubspec.yaml). Use a build number higher than every APK you want this release to update. For example, use `1.2.0+5` for tag `v1.2.0` if the previous build was 4.
2. Push the version commit to GitHub. Create a tag on that commit and push it separately. Replace the example version with yours:

   ```text
   git tag v1.2.0
   git push origin v1.2.0
   ```

   To include a short note in the update prompt, use an annotated tag, such as `git tag -a v1.2.0 -m "Improved chart navigation."`, before pushing the tag. The first paragraph is limited to 280 characters in the manifest.

3. Open **Actions → Android release** to follow the build. When it finishes, check that the stable release is marked **Latest** and has the APK, `SHA256SUMS.txt`, and `android-update.json`. The workflow uploads all three to a draft and checks their upload status before publishing. Once a release has update metadata, the workflow requires a higher versionCode before publishing the next one.

A rerun keeps a completed release and its assets. If a run finds an incomplete release or draft, inspect it in GitHub before retrying. If an existing debug install has workouts you want to keep, export a backup before uninstalling it to install the first signed release.

After publication, the workflow requests a website deployment to refresh downloads. Check the Cloudflare Pages build result as well. If the hook request fails, the release remains published. Rerun the failed publish job to retry the website refresh. A failed website build leaves the previous site live.

## Verify the first release with the updater

1. Build two APKs from the updater-enabled source with the same application ID and signing key. Choose increasing build numbers. Install the lower build on a disposable Android emulator, import [fictional workouts](testing.md#load-fictional-demo-workouts), and change a preference.
2. For a pre-publication check, serve a fixture that mirrors the public GitHub release response and its two assets over HTTPS using a test-only transport. Point the manifest at the newer APK and compute SHA-256 from that exact file. Keep the production GitHub source and certificate validation in the shipped build. The [host release tests](../test/android_release_test.dart) show the feed shape.
3. Cold-launch the older build. Check that Overview works while discovery runs. Dismiss the prompt with **Later** and relaunch to verify the 24-hour reminder for that build. Open **Profile → Check for updates** and verify that it offers the release again. Test a disconnected or failing feed, a truncated transfer, and an incorrect checksum. Leave the **App update** page during a download and reopen it from Overview. Only a complete, verified APK should offer **Install**.
4. Try **Install** with Android's source permission off. On Android 8 and later, the app opens its per-app setting. On Android 7, it opens Android security settings so you can find **Unknown sources**. Return from Settings once with the permission still off, then enable it and return. The APK should stay ready. Cancel Android's install confirmation once, then retry and confirm. Look for the newer version in **Profile** after reopening. Verify the workouts and preference survived and the prompt no longer appears.
5. Once you authorize and publish the first updater-enabled release, check the assets against the public latest-release response. The first updater-enabled version is installed manually. Its first public in-app update can be verified when a subsequent stable release is published with a higher versionCode.

The updater reads public release metadata for this repository and downloads its signed APK after the user opts in. It compares Android build numbers and ignores drafts, prereleases, and builds already installed. The workout database and profile stay on the device. Android controls the install confirmation and may restrict installs through device policy. After installation, use **Open** if Android offers it or reopen from the launcher.
