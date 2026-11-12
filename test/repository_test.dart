import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:fitness_tracker/core/database/database.dart'
    show TrackerDatabase;
import 'package:fitness_tracker/core/database/tracker_repository.dart';
import 'package:fitness_tracker/features/data_transfer/import_plan.dart';
import 'package:fitness_tracker/features/data_transfer/transfer_codec.dart';
import 'package:fitness_tracker/shared/domain/body_metrics.dart';
import 'package:fitness_tracker/shared/domain/training.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

final now = DateTime(2026, 11, 12, 14);
final today = CalendarDay.fromDate(now);
const all = (start: null, end: null);

EntryDraft record(Exercise x, String iso, List<int> values, {String? notes}) =>
    EntryDraft(
      exerciseId: x.id,
      day: CalendarDay.parse(iso),
      notes: notes,
      sets: values.map((value) => (id: null, value: value, reps: null)),
    );

Database createHistoricalDatabase(String path, int version) {
  final schema = jsonDecode(
    File('docs/schema/drift_schema_v$version.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final database = sqlite3.open(path);
  try {
    for (final entity in schema['fixed_sql'] as List<dynamic>) {
      for (final statement in entity['sql'] as List<dynamic>) {
        if (statement['dialect'] == 'sqlite') {
          database.execute(statement['sql'] as String);
        }
      }
    }
    database.execute('PRAGMA user_version = $version');
    return database;
  } catch (_) {
    database.close();
    rethrow;
  }
}

void main() {
  // A few tests keep two isolated database files open to compare snapshots.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late TrackerRepository repo;
  setUp(
    () => repo = TrackerRepository(
      TrackerDatabase(NativeDatabase.memory()),
      now: () => now,
    ),
  );
  tearDown(() => repo.close());

  test(
    'analytics distinguish latest, best, and total; edits preserve order',
    () async {
      final push = await repo.createExercise(
        '  Push-ups ',
        Measurement.repetitions,
      );
      final records = [
        record(push, '2026-10-06', [10]),
        record(push, '2026-10-12', [12]),
        record(push, '2026-10-19', [15]),
        record(push, '2026-10-28', [14]),
        record(push, '2026-11-04', [18]),
        record(push, '2026-11-12', [22, 20, 18]),
      ];
      // Log in a different date order, including older dates after the newest.
      await repo.log(records.reversed.toList());
      final data = await repo.watchPerformance(push.id, all).first;
      expect(
        [
          data.first,
          data.latest,
          data.best,
          data.change,
          data.percent,
          data.total,
          data.setCount,
          data.days.length,
        ],
        [10, 18, 22, 8, 80, 129, 8, 6],
      );
      expect(data.days.last.total, 60);
      expect(data.days.last.best, 22);
      final overview = (await repo.watchOverview().first).exercises.single;
      expect([overview.first, overview.latest, overview.best], [10, 18, 22]);
      final range = await repo.watchPerformance(push.id, (
        start: CalendarDay.parse('2026-10-28'),
        end: CalendarDay.parse('2026-11-04'),
      )).first;
      expect(range.days.map((d) => d.day.iso), ['2026-10-28', '2026-11-04']);
      expect(range.total, 32);
      await repo.log([
        record(push, '2026-11-12', [11]),
      ]);
      final latestDate = await repo.watchEntries(day: today).first;
      final older = latestDate.last;
      await repo.updateEntry(
        older,
        EntryDraft(
          exerciseId: push.id,
          day: today,
          sets: [
            (id: older.sets.first.id, value: 25, reps: null),
            ...older.sets
                .skip(1)
                .map((s) => (id: s.id, value: s.value, reps: null)),
          ],
        ),
      );
      final edited = (await repo.watchEntries(day: today).first).last;
      expect(edited.order, older.order);
      expect(edited.sets.first.id, older.sets.first.id);
      final after = await repo.watchPerformance(push.id, all).first;
      expect([after.latest, after.best], [11, 25]);
      await repo.deleteEntry(older.id);
      expect((await repo.watchPerformance(push.id, all).first).best, 18);
    },
  );

  test(
    'empty production schema, unique names, archive and restore, locked units',
    () async {
      await repo.open();
      expect((await repo.watchOverview().first).exercises, isEmpty);
      final x = await repo.createExercise('Wall Sit', Measurement.duration);
      await expectLater(
        repo.createExercise(' wall   sit ', Measurement.duration),
        throwsA(isA<TrackerException>()),
      );
      await repo.log([
        record(x, '2026-11-12', [70, 65]),
      ]);
      await expectLater(
        repo.editExercise(x.id, 'Wall Sit', Measurement.repetitions),
        throwsA(isA<TrackerException>()),
      );
      await repo.editExercise(x.id, 'Wall Hold', Measurement.duration);
      await repo.setArchived(x.id, true);
      await expectLater(
        repo.log([
          record(x, '2026-11-12', [45]),
        ]),
        throwsA(isA<TrackerException>()),
      );
      expect(
        (await repo.watchCatalog().first).single.exercise.archived,
        isTrue,
      );
      expect(
        (await repo.watchCatalog().first).single.exercise.name,
        'Wall Hold',
      );
      expect((await repo.watchOverview().first).exercises, isEmpty);
      expect(await repo.watchEntries(search: 'wall').first, isEmpty);
      expect(
        await repo.watchRecordedDays(start: today, end: today).first,
        isEmpty,
      );
      expect((await repo.snapshot()).entries.single.sets, hasLength(2));
      await repo.setArchived(x.id, false);
      expect(
        (await repo.watchOverview().first).recent.single.sets,
        hasLength(2),
      );
      expect(await repo.watchRecordedDays(start: today, end: today).first, {
        today,
      });
      await repo.log([
        record(x, '2026-11-12', [55]),
      ]);
      expect((await repo.watchPerformance(x.id, all).first).setCount, 3);
    },
  );

  test(
    'deleting a recorded exercise removes only its entries, sets and goal',
    () async {
      final keep = await repo.createExercise(
        'Push-ups',
        Measurement.repetitions,
      );
      final remove = await repo.createExercise('Plank', Measurement.duration);
      await repo.log([
        record(keep, today.iso, [12]),
        record(remove, today.iso, [55, 35]),
      ]);
      await repo.saveGoal(keep.id, 20, null);
      await repo.saveGoal(remove.id, 60, null);
      await repo.setArchived(remove.id, true);

      await repo.deleteExercise(remove.id);
      final snapshot = await repo.snapshot();
      expect(snapshot.exercises.single.id, keep.id);
      expect(snapshot.entries.single.exerciseId, keep.id);
      expect(snapshot.goals.single.exerciseId, keep.id);
      expect(await repo.db.select(repo.db.exerciseSets).get(), hasLength(1));
      expect(
        (await repo.createExercise('Plank', Measurement.duration)).id,
        isNot(remove.id),
      );
    },
  );

  test(
    'exercise reset keeps body data and settings; full reset restores defaults',
    () async {
      const profile = (
        displayName: 'Sam',
        heightMillimeters: 1785,
        heightUnit: HeightUnit.ftIn,
        weightUnit: WeightUnit.lb,
      );
      const prefs = (
        appearance: Appearance.dark,
        duration: DurationStyle.seconds,
        haptics: false,
      );
      final weight = (day: today, grams: 80200);
      final photo = Uint8List.fromList([1, 2, 3]);
      await repo.saveProfileDetails(profile);
      await repo.saveProfilePhoto(photo);
      await repo.saveWeighIn(weight);
      await repo.savePreferences(prefs);
      final batch = decodeActivity(activityExample(today), today);
      Future<void> importBatch() => repo.importActivity(
        (current) => planActivity(
          current,
          batch,
          suggestMappings(batch, current.exercises),
        ).write,
      );
      await importBatch();
      await repo.saveGoal((await repo.snapshot()).exercises.first.id, 99, null);

      await repo.deleteAllExercises();
      final exercisesOnly = await repo.snapshot();
      expect(exercisesOnly.exercises, isEmpty);
      expect(exercisesOnly.entries, isEmpty);
      expect(exercisesOnly.goals, isEmpty);
      expect(exercisesOnly.receipts, isEmpty);
      expect(exercisesOnly.preferences, prefs);
      expect(exercisesOnly.body!.profile, profile);
      expect(exercisesOnly.body!.weighIns, [weight]);
      expect((await repo.watchProfile().first).photo, photo);

      await importBatch();
      await repo.resetAllData();
      final reset = await repo.snapshot();
      expect(reset.exercises, isEmpty);
      expect(reset.entries, isEmpty);
      expect(reset.receipts, isEmpty);
      expect(reset.preferences, defaultPreferences);
      expect(reset.body!.profile, defaultProfileDetails);
      expect(reset.body!.weighIns, isEmpty);
      expect((await repo.watchProfile().first).photo, isNull);
    },
  );

  test('batch and foreign key failures roll back writes', () async {
    var next = 0;
    final collisionRepo = TrackerRepository(
      TrackerDatabase(NativeDatabase.memory()),
      id: () => ['exercise', 'entry', 'set', 'entry', 'set-2'][next++],
      now: () => now,
    );
    addTearDown(collisionRepo.close);
    final x = await collisionRepo.createExercise(
      'Squat',
      Measurement.repetitions,
    );
    final draft = record(x, today.iso, [12]);
    await expectLater(collisionRepo.log([draft, draft]), throwsA(anything));
    expect((await collisionRepo.snapshot()).entries, isEmpty);
    await expectLater(
      collisionRepo.db.customStatement(
        "INSERT INTO exercise_sets (id, entry_id, position, value) VALUES ('bad', 'missing', 0, 1)",
      ),
      throwsA(anything),
    );
    await expectLater(
      collisionRepo.log([
        record(x, '2026-11-13', [4]),
      ]),
      throwsA(isA<TrackerException>()),
    );
    expect(
      await collisionRepo.db
          .customSelect('PRAGMA foreign_keys')
          .getSingle()
          .then((row) => row.read<int>('foreign_keys')),
      1,
    );
  });

  test(
    'database preserves the selected Progress exercise across reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp('v-persistence-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File(p.join(directory.path, 'v.sqlite'));
      final first = TrackerRepository(
        TrackerDatabase(NativeDatabase(file)),
        now: () => now,
      );
      final x = await first.createExercise('Plank', Measurement.duration);
      await first.log([
        record(x, today.iso, [100, 90], notes: 'Stable form'),
      ]);
      await first.saveGoal(x.id, 110, today.plusDays(5));
      await first.saveProgressExercise(x.id);
      await first.savePreferences((
        appearance: Appearance.dark,
        duration: DurationStyle.seconds,
        haptics: false,
      ));
      await first.close();
      final second = TrackerRepository(
        TrackerDatabase(NativeDatabase(file)),
        now: () => now,
      );
      addTearDown(second.close);
      final userVersion = await second.db
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(userVersion.read<int>('user_version'), 6);
      final snapshot = await second.snapshot();
      expect(snapshot.entries.single.latest, 90);
      expect(snapshot.entries.single.notes, 'Stable form');
      expect(snapshot.goals.single.target, 110);
      expect(snapshot.preferences.appearance, Appearance.dark);
      expect(await second.watchProgressExercise().first, x.id);
      await second.saveProgressExercise(x.id);
      expect((await second.snapshot()).preferences, snapshot.preferences);
      final indices = await second.db
          .customSelect("PRAGMA index_list('entries')")
          .get();
      expect(
        indices.map((i) => i.read<String>('name')),
        contains('entries_by_exercise_day'),
      );
      await second.deleteExercise(x.id);
      expect(await second.watchProgressExercise().first, isNull);
    },
  );

  test(
    'v5 upgrades without changing existing preferences or exercises',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'progress-migration-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File(p.join(directory.path, 'fitness.sqlite'));
      final old = createHistoricalDatabase(file.path, 5);
      try {
        old.execute(
          "INSERT INTO app_preferences VALUES (1, 'dark', 'seconds', 0)",
        );
        final timestamp = now.toUtc().toIso8601String();
        old.execute(
          "INSERT INTO exercises (id, name, normalized_name, measurement, created_at, updated_at) VALUES ('plank', 'Plank', 'plank', 'duration', ?, ?)",
          [timestamp, timestamp],
        );
      } finally {
        old.close();
      }
      final migrated = TrackerRepository(TrackerDatabase(NativeDatabase(file)));
      addTearDown(migrated.close);
      expect(await migrated.watchProgressExercise().first, isNull);
      expect((await migrated.snapshot()).exercises.single.id, 'plank');
      await migrated.saveProgressExercise('plank');
      expect(await migrated.watchProgressExercise().first, 'plank');
      expect((await migrated.snapshot()).preferences, (
        appearance: Appearance.dark,
        duration: DurationStyle.seconds,
        haptics: false,
      ));
    },
  );

  test('migration preserves v1 records and enables persistent body data', () async {
    final directory = await Directory.systemTemp.createTemp('fitness-v1-');
    addTearDown(() => directory.delete(recursive: true));
    final file = p.join(directory.path, 'fitness.sqlite');
    final old = createHistoricalDatabase(file, 1);
    try {
      final stamp = now.toUtc().toIso8601String();
      old.execute(
        "INSERT INTO exercises VALUES ('push', 'Push-ups', 'push-ups', 'repetitions', 0, ?, ?)",
        [stamp, stamp],
      );
      old.execute(
        "INSERT INTO entries VALUES ('entry', 'push', ?, 'Existing', 1, ?, ?)",
        [today.iso, stamp, stamp],
      );
      old.execute("INSERT INTO exercise_sets VALUES ('set', 'entry', 0, 18)");
      old.execute("INSERT INTO goals VALUES ('push', 25, NULL, ?)", [stamp]);
      old.execute("INSERT INTO app_preferences VALUES (1, 'dark', 'clock', 0)");
    } finally {
      old.close();
    }

    final migrated = TrackerRepository(
      TrackerDatabase(NativeDatabase(File(file))),
      now: () => now,
    );
    try {
      final snapshot = await migrated.snapshot();
      expect(snapshot.entries.single.latest, 18);
      expect(snapshot.entries.single.notes, 'Existing');
      expect(snapshot.entries.single.sets.single.id, 'set');
      expect(snapshot.exercises.single.trackSets, isTrue);
      expect(snapshot.goals.single.target, 25);
      expect(snapshot.preferences.appearance, Appearance.dark);
      expect(snapshot.body!.profile, defaultProfileDetails);
      await migrated.saveProfileDetails((
        displayName: 'Sam',
        heightMillimeters: 1785,
        heightUnit: HeightUnit.cm,
        weightUnit: WeightUnit.lb,
      ));
      await migrated.saveWeighIn((day: today, grams: 81250));
    } finally {
      await migrated.close();
    }

    final reopened = TrackerRepository(
      TrackerDatabase(NativeDatabase(File(file))),
    );
    addTearDown(reopened.close);
    final snapshot = await reopened.snapshot();
    expect(snapshot.entries.single.latest, 18);
    expect(snapshot.body!.profile.displayName, 'Sam');
    expect(snapshot.body!.weighIns, [(day: today, grams: 81250)]);
  });

  test('v3 profiles keep their height, avatar and weight unit', () async {
    final directory = await Directory.systemTemp.createTemp('fitness-v3-');
    addTearDown(() => directory.delete(recursive: true));
    final file = p.join(directory.path, 'fitness.sqlite');
    final old = createHistoricalDatabase(file, 3);
    try {
      old.execute('''
        INSERT INTO local_profiles
          (id, display_name, height_millimeters, weight_unit, avatar_preset)
        VALUES (1, 'Sam', 1785, 'lb', 'running')
      ''');
    } finally {
      old.close();
    }
    final migrated = TrackerRepository(
      TrackerDatabase(NativeDatabase(File(file))),
    );
    addTearDown(migrated.close);
    final profile = await migrated.watchProfile().first;
    expect(profile.details, (
      displayName: 'Sam',
      heightMillimeters: 1785,
      heightUnit: HeightUnit.cm,
      weightUnit: WeightUnit.lb,
    ));
    expect(profile.avatarPreset, AvatarPreset.running);
  });

  test(
    'v2 migration keeps gallery photos and persists preset choices',
    () async {
      final directory = await Directory.systemTemp.createTemp('fitness-v2-');
      addTearDown(() => directory.delete(recursive: true));
      final file = p.join(directory.path, 'fitness.sqlite');
      final photo = Uint8List.fromList([1, 2, 3]);
      final old = createHistoricalDatabase(file, 2);
      try {
        old.execute(
          "INSERT INTO local_profiles (id, display_name, weight_unit, photo) VALUES (1, 'Sam', 'lb', ?)",
          [photo],
        );
        old.execute('INSERT INTO weigh_ins (day, grams) VALUES (?, 80000)', [
          today.iso,
        ]);
      } finally {
        old.close();
      }

      final migrated = TrackerRepository(
        TrackerDatabase(NativeDatabase(File(file))),
      );
      try {
        final profile = await migrated.watchProfile().first;
        expect(profile.avatarPreset, AvatarPreset.anonymous);
        expect(profile.photo, photo);
        await migrated.saveProfileAvatar(AvatarPreset.strength);
        expect((await migrated.watchProfile().first).photo, isNull);
        await migrated.saveProfilePhoto(photo);
        await migrated.saveProfilePhoto(null);
      } finally {
        await migrated.close();
      }

      final reopened = TrackerRepository(
        TrackerDatabase(NativeDatabase(File(file))),
      );
      addTearDown(reopened.close);
      final profile = await reopened.watchProfile().first;
      expect(profile.avatarPreset, AvatarPreset.strength);
      expect(profile.details.displayName, 'Sam');
      expect(profile.details.weightUnit, WeightUnit.lb);
      expect((await reopened.snapshot()).body!.weighIns, [
        (day: today, grams: 80000),
      ]);
    },
  );

  test(
    'weigh-in edits preserve date order and reject duplicates and stale edits',
    () async {
      final older = (day: today.plusDays(-10), grams: 81350);
      final latest = (day: today, grams: 80950);
      await repo.saveWeighIn(latest, displayUnit: WeightUnit.lb);
      await repo.saveWeighIn(older);
      expect(await repo.watchWeighIns(limit: 1).first, [latest]);
      await expectLater(
        repo.saveWeighIn(latest, displayUnit: WeightUnit.kg),
        throwsA(isA<TrackerException>()),
      );
      expect(
        (await repo.watchProfile().first).details.weightUnit,
        WeightUnit.lb,
      );
      await expectLater(
        repo.saveWeighIn((day: today.plusDays(1), grams: 80400)),
        throwsA(isA<TrackerException>()),
      );
      await expectLater(
        repo.saveWeighIn((
          day: latest.day,
          grams: older.grams,
        ), original: older),
        throwsA(isA<TrackerException>()),
      );
      final corrected = (day: older.day.plusDays(1), grams: 81400);
      await repo.saveWeighIn(corrected, original: older);
      await expectLater(
        repo.deleteWeighIn(older),
        throwsA(isA<TrackerException>()),
      );
      expect(await repo.watchWeighIns().first, [latest, corrected]);
      await repo.deleteWeighIn(latest);
      expect(await repo.watchWeighIns(limit: 1).first, [corrected]);
    },
  );

  test('backup restores measurements while the photo and legacy omissions stay local', () async {
    const localDetails = (
      displayName: 'Sam',
      heightMillimeters: 1785,
      heightUnit: HeightUnit.ftIn,
      weightUnit: WeightUnit.lb,
    );
    final weight = (day: today, grams: 80000);
    final photo = Uint8List.fromList([1, 2, 3]);
    await repo.saveProfilePhoto(photo);
    await repo.saveProfileDetails(localDetails);
    await repo.saveWeighIn(weight);
    final profile = await repo.watchProfile().first;
    expect(profile.photo, photo);
    expect(profile.details, localDetails);
    final current = await repo.snapshot();
    final backup = encodeBackup(current, now);
    expect(backup, contains('"schemaVersion": 3'));
    expect(decodeBackup(backup, today).body!.profile, localDetails);
    expect(backup, isNot(contains('"photo"')));
    expect(
      backupFingerprint(decodeBackup(backup, today)),
      backupFingerprint(current),
    );
    final legacy = BackupData(
      exercises: [],
      entries: [],
      goals: [],
      preferences: defaultPreferences,
      receipts: {},
    );
    final oldBackup = decodeBackup(encodeBackup(legacy, now), today);
    await repo.restore(
      (local) => planBackup(local, oldBackup, RestoreMode.replace).write,
      recover: (_) async {},
    );
    expect((await repo.snapshot()).body!.weighIns, [weight]);
    expect((await repo.watchProfile().first).details, localDetails);

    final replacement = BackupData(
      exercises: [],
      entries: [],
      goals: [],
      preferences: defaultPreferences,
      receipts: {},
      body: BodyData(defaultProfileDetails, []),
    );
    await repo.restore(
      (local) => planBackup(local, replacement, RestoreMode.replace).write,
      recover: (local) async => expect(local.body!.weighIns, [weight]),
    );
    final restored = await repo.watchProfile().first;
    expect(restored.details, defaultProfileDetails);
    expect(restored.photo, photo);
    expect(await repo.watchWeighIns().first, isEmpty);
  });

  test(
    'restore preserves IDs, positions, goals, settings and receipts atomically',
    () async {
      final batch = decodeActivity(activityExample(today), today);
      await repo.importActivity(
        (current) => planActivity(
          current,
          batch,
          suggestMappings(batch, current.exercises),
        ).write,
      );
      final initial = await repo.snapshot();
      final x = initial.exercises.first;
      await repo.saveGoal(x.id, 99, today.plusDays(1));
      await repo.savePreferences((
        appearance: Appearance.dark,
        duration: DurationStyle.seconds,
        haptics: false,
      ));
      final source = await repo.snapshot();
      final parsed = decodeBackup(encodeBackup(source, now), today);
      final pullUps = parsed.exercises.singleWhere((x) => x.name == 'Pull-ups');
      expect(pullUps.trackSets, isFalse);
      expect(
        parsed.entries.singleWhere((e) => e.exerciseId == pullUps.id).latest,
        0,
      );
      final bench = parsed.exercises.singleWhere(
        (x) => x.name == 'Bench press',
      );
      expect(
        parsed.entries
            .singleWhere((e) => e.exerciseId == bench.id)
            .sets
            .single
            .reps,
        8,
      );
      expect(encodeCsv(parsed), contains(',60,8,'));
      expect(encodeCsv(parsed), contains(',0,,"Could not complete a rep."'));
      expect(backupFingerprint(parsed), backupFingerprint(source));
      expect(
        planBackup(source, parsed, RestoreMode.merge).write.data.entries,
        isEmpty,
      );

      final other = TrackerRepository(
        TrackerDatabase(NativeDatabase.memory()),
        now: () => now,
      );
      addTearDown(other.close);
      await other.createExercise('Old activity', Measurement.repetitions);
      final oldHash = backupFingerprint(await other.snapshot());
      await expectLater(
        other.restore(
          (current) => planBackup(current, parsed, RestoreMode.replace).write,
          recover: (_) async => throw FileSystemException('disk full'),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(backupFingerprint(await other.snapshot()), oldHash);
      String? recovered;
      await other.restore(
        (current) => planBackup(current, parsed, RestoreMode.replace).write,
        recover: (current) async => recovered = backupFingerprint(current),
      );
      expect(recovered, oldHash);
      expect(
        backupFingerprint(await other.snapshot()),
        backupFingerprint(source),
      );
      expect(
        (await other.snapshot()).receipts.keys,
        contains(batch.fingerprint),
      );
    },
  );

  test(
    'repeat receipts block a second write unless explicitly authorized',
    () async {
      final batch = decodeActivity(activityExample(today), today);
      ActivityWrite plan(BackupData current) => planActivity(
        current,
        batch,
        suggestMappings(batch, current.exercises),
      ).write;
      await repo.importActivity(plan);
      final original = backupFingerprint(await repo.snapshot());
      await expectLater(
        repo.importActivity(plan),
        throwsA(isA<TrackerException>()),
      );
      expect(backupFingerprint(await repo.snapshot()), original);
      await repo.importActivity(plan, allowRepeat: true);
      final repeated = await repo.snapshot();
      expect(repeated.entries, hasLength(batch.records.length * 2));
      expect(repeated.receipts, hasLength(1));
    },
  );

  test(
    '10,000 recorded sets keep exact stats, while history reads one page',
    () async {
      final x = await repo.createExercise(
        'Large fixture',
        Measurement.repetitions,
      );
      await repo.log([
        for (var i = 0; i < 100; i++)
          record(
            x,
            today.plusDays(i - 99).iso,
            List.generate(100, (set) => (i + 1) + set % 3),
          ),
      ]);
      final data = await repo.watchPerformance(x.id, all).first;
      expect(data.days.length, 100);
      expect(data.setCount, 10000);
      expect(data.latest, 100);
      expect(data.best, 102);
      expect(data.total, 514900);
      expect(
        (await repo.watchOverview().first).exercises.single.trend,
        hasLength(16),
      );
      expect(await repo.watchEntries(limit: 21).first, hasLength(21));
      final snapshot = await repo.snapshot();
      expect(
        decodeBackup(encodeBackup(snapshot, now), today).entries.length,
        100,
      );
    },
  );
}
