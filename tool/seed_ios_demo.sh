#!/bin/sh
# Seed a booted iOS simulator selected by the contributor.
set -eu
cd "$(dirname "$0")/.."

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Usage: $0 SIMULATOR_UDID [YYYY-MM-DD]" >&2
  exit 64
fi

device="$1"
app=tn.dhibi.fitness-tracker
day="${2:-$(date +%F)}"
xcrun simctl list devices booted -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
if not any(
    d["udid"] == sys.argv[1]
    for runtime, group in devices.items()
    if runtime.startswith("com.apple.CoreSimulator.SimRuntime.iOS-")
    for d in group
):
    sys.exit("Choose an explicit UDID for a booted iOS simulator.")
' "$device"
data="$(xcrun simctl get_app_container "$device" "$app" data)"
xcrun simctl terminate "$device" "$app" >/dev/null 2>&1 || true
dart run tool/seed_simulator_data.dart "$day" "$data/Library/Application Support/fitness.sqlite" build/qa/v-demo-data.json
xcrun simctl launch "$device" "$app"
