# Testing

| Task | Where to run it | Extra tools |
| --- | --- | --- |
| Format, analyze, run host tests, or generate a demo backup | Windows, macOS, Linux | Standard Flutter installation |
| Build or test Android | Windows, macOS, Linux | Android SDK. Use an emulator or connected device for integration tests. |
| Build or test iOS | macOS | Xcode. Use a simulator or a signed test device for integration tests. |
| Refresh the README gallery | macOS | Xcode with the documented simulator runtime, and WebP tools |

The scripts in `tool/` ending in `.sh` call Apple's simulator tools. They are optional and macOS only. On Windows, run the shared commands in PowerShell without WSL or Git Bash.

## Run host checks

Run these commands from the repository root. The first run downloads dependencies, including the native SQLite library used by the tests.

```text
flutter pub get
dart format --output=none --set-exit-if-changed lib test integration_test tool
flutter analyze
flutter test
```

Use `flutter test --coverage` to write the coverage report to `coverage/lcov.info`. The host suite covers domain rules, SQLite and migrations, imports and exports, and widget behavior.

## Run device checks when needed

Use `flutter devices` to find a target. Choose an Android emulator or connected Android device on Windows, macOS, or Linux. On macOS with Xcode, you can also choose an iOS simulator or connected iOS device. Use a disposable test target: Flutter may replace or remove the app during an integration run.

```text
flutter test integration_test/fitness_flow_test.dart -d DEVICE_ID
```

Replace `DEVICE_ID` with your selected ID. This suite checks logging, history, goals, imports, and profile settings using test databases. On iOS it saves diagnostic images to the test app's temporary directory. The [README screenshot exporter](screenshots.md) runs separately.

To check an Android build, run `flutter build apk --debug`. On macOS, run `flutter build ios --simulator --debug` for an iOS simulator build. On macOS only, open `ios/Runner.xcworkspace` in Xcode and run the **NativeSmoke** scheme on your chosen simulator to exercise the iOS share sheet, file picker, and system navigation.

## Load fictional demo workouts

Run this from the repository root after `flutter pub get`:

```text
dart run tool/export_demo_backup.dart
```

This writes `build/qa/v-demo-data.json`. You can pass a different output path as the first argument. Use a disposable test install to keep the sample workouts separate from your own.

To copy the backup to an Android emulator, start the emulator in Android Studio's **Device Manager**. Run these commands with Android SDK Platform Tools on your PATH:

```text
adb devices
adb -s ANDROID_SERIAL push build/qa/v-demo-data.json /sdcard/Download/v-demo-data.json
```

Replace `ANDROID_SERIAL` with your emulator's serial from `adb devices`. You can also copy the JSON file to a physical test device using your usual file transfer method.

In Fitness Tracker, open **Profile → Your data → Import backup → Open JSON file**. On Android, find `v-demo-data.json` in **Recent** or **Downloads**. Keep **Merge with local data** selected and tap **Merge backup**. Return to **Overview** to see the sample exercises.

### Seed a local iOS simulator directly

On macOS with Python 3 installed, you can also seed an empty iOS simulator install directly. Install and run the app on the simulator first:

```sh
./tool/seed_ios_demo.sh DEVICE_ID
```

The loader leaves existing workouts alone. For README images, use the [screenshot command](screenshots.md). It has its own temporary simulator and database.
