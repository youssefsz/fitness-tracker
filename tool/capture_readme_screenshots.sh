#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

for command in flutter xcrun cwebp; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Missing $command. See docs/screenshots.md for setup." >&2
    exit 1
  fi
done

mkdir -p build
captures="$(mktemp -d "$PWD/build/readme-screenshots.XXXXXX")"
device=''
cleanup() {
  if [ -n "$device" ]; then
    xcrun simctl shutdown "$device" >/dev/null 2>&1 || true
    xcrun simctl delete "$device" || true
  fi
  rm -rf "$captures"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

device="$(xcrun simctl create "Fitness Tracker README" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-17 \
  com.apple.CoreSimulator.SimRuntime.iOS-27-0)"
xcrun simctl bootstatus "$device" -b
xcrun simctl status_bar "$device" override \
  --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryLevel 100

flutter test integration_test/readme_screenshots_test.dart -d "$device" \
  --dart-define="README_SCREENSHOT_DIR=$captures"

# Finish all four captures before replacing the README images.
for screen in overview progress history log; do
  cwebp -quiet -lossless -resize 804 0 "$captures/$screen.png" -o "$captures/$screen.webp"
done
mkdir -p docs/screenshots
for screen in overview progress history log; do
  mv "$captures/$screen.webp" "docs/screenshots/$screen.webp"
done
echo "Updated Overview, Progress, History, and Log in docs/screenshots/."
