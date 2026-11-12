# V

V is an offline exercise log for iPhone, iPad, and Android. Record reps or timed sets, compare results, and keep a portable backup. The app starts with an empty log.

## Run the app

Use Flutter 3.47.5 with Dart 3.13.4. The iOS build was developed with Xcode 27.0. Run these commands from the project root:

```sh
flutter pub get
flutter run -d 15D09C3D-812A-408D-B323-8C56BE563D82
```

The device ID above is the designated iPhone 17 simulator on the development host. See [Testing](TESTING.md) for checks and device restrictions. The Apple bundle ID is `tn.dhibi.fitness-tracker`. Android application IDs disallow hyphens, so the Android ID is `tn.dhibi.fitness_tracker`.

## Work on the app

- Read [Architecture](ARCHITECTURE.md) for SQLite, state, and analytics rules.
- Read [Data formats](DATA_FORMAT.md) before changing backup or activity import.
- See [Design](DESIGN.md) for the visual system and [the original references](docs/reference/) for screenshots and raster brand masters.
- To change the Drift schema, edit `lib/core/database/database.dart`. Regenerate `database.g.dart` with `dart run build_runner build`. Bump the schema version, add the migration and its tests, then run `dart run drift_dev schema dump lib/core/database/database.dart docs/schema`.

## Regenerate the brand assets

Edit the display name in `tool/brand.json` and the version in `pubspec.yaml`. On macOS with Python and Pillow installed, run:

```sh
python3 tool/generate_brand_assets.py
```

The supplied raster masters live in `docs/reference/brand`. The generator produces the Flutter logo in `assets/brand`, the iOS icon and launch catalogs, and the Android launcher and splash assets. The favicon is reference material because this project targets native mobile. The screen reference PNGs are documentation and are excluded from the application bundle.

## Load the simulator demo

The installed copy on the designated iPhone 17 can hold eight months of fictional activity for testing. The sample includes both measurement types, goals in different states, an archived exercise, and multiple entries on some dates. It does not load on a fresh install.

To seed an empty installed copy on that simulator, run:

```sh
tool/seed_iphone17.sh
```

The script checks the simulator and preserves existing activity. It also writes the original demo snapshot to `build/qa/v-demo-data.json`. You can import that file through Settings to try the merge or restore flow. Treat the demo as fictional activity.
