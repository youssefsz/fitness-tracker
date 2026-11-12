import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:fitness_tracker/core/database/database.dart'
    show TrackerDatabase;
import 'package:fitness_tracker/core/database/tracker_repository.dart';
import 'package:fitness_tracker/features/data_transfer/import_plan.dart';
import 'package:fitness_tracker/features/data_transfer/transfer_codec.dart';
import 'package:fitness_tracker/shared/domain/training.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

final now = DateTime(2026, 11, 12, 14);
final today = CalendarDay.fromDate(now);
const all = (start: null, end: null);

EntryDraft record(Exercise x, String iso, List<int> values, {String? notes}) =>
    EntryDraft(
      exerciseId: x.id,
      day: CalendarDay.parse(iso),
      notes: notes,
      sets: values.map((value) => (id: null, value: value)),
    );

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
            (id: older.sets.first.id, value: 25),
            ...older.sets.skip(1).map((s) => (id: s.id, value: s.value)),
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
      await repo.setArchived(x.id, false);
      await repo.log([
        record(x, '2026-11-12', [55]),
      ]);
      expect((await repo.watchPerformance(x.id, all).first).setCount, 3);
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

  test('new database has v1 schema and survives close and reopen', () async {
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
    expect(userVersion.read<int>('user_version'), 1);
    final snapshot = await second.snapshot();
    expect(snapshot.entries.single.latest, 90);
    expect(snapshot.entries.single.notes, 'Stable form');
    expect(snapshot.goals.single.target, 110);
    expect(snapshot.preferences.appearance, Appearance.dark);
    final indices = await second.db
        .customSelect("PRAGMA index_list('entries')")
        .get();
    expect(
      indices.map((i) => i.read<String>('name')),
      contains('entries_by_exercise_day'),
    );
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
      expect(repeated.entries, hasLength(4));
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
