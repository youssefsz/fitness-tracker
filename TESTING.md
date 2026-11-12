# Testing

Run the host checks from the project root:

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test --coverage
```

The tests cover calendar boundaries, latest versus best, backfills, ordered edits, archive and restore, goals, JSON validation, duplicate import rules, CSV escaping, persistence, foreign keys, and transaction rollback. A generated 10,000-set fixture checks exact aggregates and paged history reads. Widget tests cover loading and retry, form validation, retained drafts, repeated saves, haptic dispatch, and responsive navigation at 320, 430, and 1,024 logical points with text up to 2×.

## Build and device commands

Device-based testing is restricted to the iPhone 17 simulator running iOS 27.0, runtime build 24A434, UDID `15D09C3D-812A-408D-B323-8C56BE563D82`.

```sh
xcrun simctl list devices available
xcrun simctl list runtimes
flutter build ios --simulator --debug --no-codesign
flutter test integration_test/fitness_flow_test.dart -d 15D09C3D-812A-408D-B323-8C56BE563D82
flutter build apk --debug
```

The integration tests use temporary databases. Screenshots are written to `tmp/v-integration-captures` in the simulator app data container. The production startup has no test fixtures.

To retain screenshots directly in the project, pass `--dart-define=V_QA_PATH="$PWD/build/qa"` to the integration command. The Flutter integration tests stub keyboard text transport for deterministic entry on the simulator.

The simulator demo loader is separate from the test suite. Run device tests before seeding so test installs and uninstalls cannot remove the demo database.

## Native iOS smoke test

After `flutter pub get`, prepare the iOS build settings and run the native scheme:

```sh
flutter build ios --simulator --debug --no-codesign --config-only
xcodebuild test -workspace ios/Runner.xcworkspace -scheme NativeSmoke \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=15D09C3D-812A-408D-B323-8C56BE563D82' \
  -parallel-testing-enabled NO \
  -derivedDataPath "$PWD/build/native-smoke" \
  CODE_SIGNING_ALLOWED=NO FLUTTER_TARGET="$PWD/lib/main.dart"
```

XCTest uses the actual iOS share sheet and document picker. It checks cancellation in both and checks that the import screen remains open after backgrounding and resuming.

## Results

- Formatting and static analysis passed.
- All 24 host tests passed with coverage enabled.
- Both Flutter integration tests passed on the designated iPhone 17. They exercised backdated logging for both measurement types, multiple sets, edits and deletes, ranges and chart values, goals, archive and restore, database reopening, malformed AI input, and duplicate AI imports.
- The native XCTest passed on the same simulator. It opened and dismissed the system share sheet and document picker, then verified background and resume.
- The iOS simulator build and Android debug APK build passed. The built IDs were `tn.dhibi.fitness-tracker` and `tn.dhibi.fitness_tracker`, respectively.
- The shipped Flutter logo is 5.8 KiB. The screenshot references and raster masters are excluded from the app assets.

No Android or iPad device was launched. Host widgets cover narrow phones and a tablet-sized layout. Saving to an external share destination, selecting an external file from the native picker, physical haptics, and release performance were outside these checks.
