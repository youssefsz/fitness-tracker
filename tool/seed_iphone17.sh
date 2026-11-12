#!/bin/sh
# Seed the installed production app on the designated simulator only.
set -eu
cd "$(dirname "$0")/.."
device=15D09C3D-812A-408D-B323-8C56BE563D82
app=tn.dhibi.fitness-tracker
day="${1:-$(date +%F)}"
xcrun simctl list devices booted -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"].get("com.apple.CoreSimulator.SimRuntime.iOS-27-0", [])
assert any(d["udid"] == sys.argv[1] and d["deviceTypeIdentifier"] ==
           "com.apple.CoreSimulator.SimDeviceType.iPhone-17" for d in devices), "Expected the designated booted iPhone 17."
' "$device"
data="$(xcrun simctl get_app_container "$device" "$app" data)"
xcrun simctl terminate "$device" "$app" >/dev/null 2>&1 || true
dart run tool/seed_simulator_data.dart "$day" "$data/Library/Application Support/fitness.sqlite" build/qa/v-demo-data.json
xcrun simctl launch "$device" "$app"
