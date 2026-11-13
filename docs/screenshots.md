# Refresh README screenshots

The README uses four WebP images in [docs/screenshots](screenshots/): Overview, Progress, History, and Log. The capture test opens the current app with [fictional workouts](../tool/demo_data.dart), a fixed date, and light appearance. The app reads a temporary in-memory SQLite database. No account, Firebase project, or personal backup is needed.

On macOS, install Flutter, Xcode with the iOS 27 simulator runtime, and the WebP tools (`brew install webp` if you use Homebrew). Run from the repository root:

```sh
./tool/capture_readme_screenshots.sh
```

The script creates an iPhone 17 simulator for consistent framing and removes it when the run finishes. It replaces the four images after all captures and conversions succeed. Your existing simulators and app data are left alone.

Review the four images in the README before including them in a change. Contributors on other platforms can run the [host checks](testing.md) and note that the iOS image refresh is pending. The screenshot command is local and does not run as part of the host test suite.
