# Architecture

A form submits one immutable batch of entries. The repository validates the batch and writes it in one SQLite transaction. Riverpod subscribes to Drift queries, so Overview, Progress, and History see committed results without copying records into UI state. Unsaved form state belongs to the form.

The schema has exercises, entries, sets, goals, preferences, import receipts, a local profile, and weigh-ins. Exercise, entry and set IDs are opaque UUIDs. An entry owns its sets and a stable order number. Within a calendar date, the highest entry order and last set position determine the latest set. Editing retains the entry order. Dates use ISO calendar text. Audit times use UTC. Foreign keys, unique names and positions, checks, and date indexes protect the stored model.

The repository exposes exercise catalogs, dated views, analytics inputs and mutation methods. A pure Dart domain module owns the rules for calendar arithmetic and performance statistics. Transfer formats are validated outside the transaction. A preview is tied to the snapshot it was computed from, and the write transaction checks that snapshot again.

An alternative was to hold the full database in a Riverpod notifier. That simplifies reads at first, but makes large histories expensive and introduces a second copy of the truth. Queries instead load the needed date window or page. Transfers deliberately read a consistent full snapshot.

The app has one local profile. Height is stored in millimeters and each calendar day can have one body-weight reading in grams. Profile shows the latest reading by measurement date. The photo is resized on import and stored in the local database. JSON backups carry profile details and weigh-ins.

Implementation checkpoints: persist and verify the logging loop; build the dated views and goals; complete portable formats; check platform assets and responsive layouts; run host tests and the designated simulator.

## Reading records

`TrackerRepository` owns the SQL and the write transactions. On mobile, Drift runs SQLite on a background isolate. Overview fetches one summary and at most 16 recent days per exercise. Performance queries return one aggregate per recorded date for the selected exercise. History and exercise detail query one page at a time. The history search filters on normalized exercise names before paging.

Seven, 30, 90, and 365-day ranges include the current local date. Custom dates are inclusive. A goal with a deadline uses the best set on or before that date. The chart positions each mark by calendar day and leaves unrecorded dates without marks. When marks outnumber available pixels, four-pixel buckets keep local extrema for lines and the largest bar for volume. Totals and the list of exact values use all recorded dates.

## Dependencies

Riverpod supplies database streams and injectable platform services. GoRouter keeps the three primary tabs alive independently. Drift uses SQLite through `sqlite3`. `file_selector` opens JSON files, `share_plus` opens the system share sheet, and `path_provider` locates private storage. `image_picker` opens the system photo library. `package_info_plus` reads the installed version and build. `crypto` hashes import receipts, `uuid` creates record IDs, `intl` formats dates, and Lucide supplies line icons. The app uses Flutter's clipboard and haptics APIs.

The resolved package versions are in `pubspec.lock`. The Profile footer links to the Flutter license registry. The app has no network service or AI SDK.
