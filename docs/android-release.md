# Release an Android APK

The Android release workflow builds one installable APK for the architectures supported by Flutter. It checks the tagged source and the APK signature before publishing the APK and a SHA-256 checksum on GitHub. Release downloads follow the repository's visibility.

## Back up the signing key

Keep an encrypted backup of the PKCS#12 keystore and save its password in your password manager. Use the same signing key for every release so Android can update existing installations. The key alias is `fitness-tracker`. [Android app signing](https://developer.android.com/studio/publish/app-signing)

The [certificate fingerprint](../android/release-signing.sha256) is public. The workflow compares it with the certificate in the finished APK. Keep the private keystore and password outside the repository.

## Configure GitHub once

In your repository settings, open **Secrets and variables → Actions** and create these repository secrets:

| Secret | Value |
| --- | --- |
| `ANDROID_RELEASE_KEYSTORE_BASE64` | The PKCS#12 keystore encoded as Base64 |
| `ANDROID_RELEASE_PASSWORD` | The keystore password |

With the GitHub CLI, you can pipe secrets into `gh secret set NAME --repo OWNER/REPO` instead of copying them through the clipboard. Base64 represents binary data as text. Treat the encoded keystore as private. [GitHub Actions secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets)

## Build a signed APK locally

Set `ANDROID_RELEASE_KEYSTORE` to the absolute path of the keystore. Load `ANDROID_RELEASE_PASSWORD` from your password manager or credential store into the environment of the build. Run these commands from the repository root:

```text
flutter pub get --enforce-lockfile
flutter build apk --release
```

Find the APK at `build/app/outputs/flutter-apk/app-release.apk`. Use `apksigner verify --verbose --print-certs` from Android SDK Build Tools to verify it and compare the certificate's SHA-256 digest with the repository fingerprint. Debug builds use the standard Android debug key and require no release credentials.

## Publish a version

1. Update the version and increase the build number in [pubspec.yaml](../pubspec.yaml). For example, use `1.2.0+3` for tag `v1.2.0`.
2. Push the version commit to GitHub. Create a tag on that commit and push it separately. Replace the example version with yours:

   ```text
   git tag v1.2.0
   git push origin v1.2.0
   ```

3. Open **Actions → Android release** to follow the build. When it finishes, check that the GitHub Release has the APK and `SHA256SUMS.txt`.

A rerun keeps a completed release and its assets. If a run finds an incomplete release or draft, inspect it in GitHub before retrying. If an existing debug install has workouts you want to keep, export a backup before uninstalling it to install the first signed release.
