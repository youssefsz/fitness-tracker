# Development

Use the [README setup](../README.md#run-locally) to install Flutter and choose a target. See [Testing](testing.md) for host checks and platform-specific commands.

## Find the code

| Path | Purpose |
| --- | --- |
| [lib/app](../lib/app/) | Navigation, providers, and themes |
| [lib/features](../lib/features/) | Screens and behavior by feature |
| [lib/core](../lib/core/) | SQLite access and platform services |
| [lib/shared](../lib/shared/) | Domain rules and reusable widgets |
| [test](../test/) and [integration_test](../integration_test/) | Host and device tests |
| [landing-page](../landing-page/) | Static marketing site, separate from the Flutter app |

## Change the database schema

1. Edit [database.dart](../lib/core/database/database.dart). Bump the schema version and add a migration for existing installs.
2. Regenerate the Drift code and export the new schema snapshot:

   ```text
   dart run build_runner build
   dart run drift_dev schema dump lib/core/database/database.dart docs/schema
   ```

3. Add a migration test that opens an older snapshot and verifies the existing records survive. Keep the older [schema snapshots](schema/) for migration tests.
4. For backup or import changes, update the [format reference](data-formats.md) and test compatibility with existing files.

## Regenerate app branding

Edit [brand.json](../tool/brand.json) or the [source artwork](../tool/brand_sources/). This optional task needs Python 3.9 or newer and Pillow. It does not need a simulator or Xcode.

On Windows, run these commands in PowerShell:

```powershell
py -3 -m venv .local/brand-venv
./.local/brand-venv/Scripts/python.exe -m pip install Pillow
./.local/brand-venv/Scripts/python.exe tool/generate_brand_assets.py
```

On macOS or Linux:

```sh
python3 -m venv .local/brand-venv
.local/brand-venv/bin/python -m pip install Pillow
.local/brand-venv/bin/python tool/generate_brand_assets.py
```

The generator writes the Flutter mark and the iOS and Android app icons and launch assets.

Set the app version and build number in [pubspec.yaml](../pubspec.yaml) or pass them through Flutter's build flags. The Profile footer reads them from the installed build.
