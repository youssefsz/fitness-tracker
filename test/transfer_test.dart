import 'dart:convert';

import 'package:fitness_tracker/features/data_transfer/import_plan.dart';
import 'package:fitness_tracker/features/data_transfer/transfer_codec.dart';
import 'package:fitness_tracker/shared/domain/body_metrics.dart';
import 'package:fitness_tracker/shared/domain/training.dart';
import 'package:flutter_test/flutter_test.dart';

final today = CalendarDay.parse('2026-11-12');
final time = DateTime.utc(2026, 11, 12, 14);
BackupData data({
  List<Exercise> exercises = const [],
  List<Entry> entries = const [],
  Map<String, DateTime> receipts = const {},
  BodyData? body,
  Preferences preferences = defaultPreferences,
}) => BackupData(
  exercises: exercises,
  entries: entries,
  goals: [],
  preferences: preferences,
  receipts: receipts,
  body: body,
);
Exercise exercise(
  String id,
  String name,
  Measurement measurement, {
  bool archived = false,
}) => Exercise(
  id: id,
  name: name,
  measurement: measurement,
  archived: archived,
  createdAt: time,
  updatedAt: time,
);

Entry entry(
  String id,
  String exercise,
  List<int> sets, {
  int order = 1,
  String? notes,
}) => Entry(
  id: id,
  exerciseId: exercise,
  day: today,
  notes: notes,
  order: order,
  createdAt: time,
  updatedAt: time,
  sets: [
    for (final (i, value) in sets.indexed)
      (id: '$id-$i', position: i, value: value, reps: null),
  ],
);

void main() {
  test('AI example and copied prompt share the validated contract', () {
    final example = activityExample(today);
    final batch = decodeActivity(example, today);
    expect(batch.records.first.sets.map((s) => s.value), [22, 20, 18]);
    expect(batch.records[1].sets.map((s) => s.value), [100, 90]);
    expect(batch.records[2].sets.single.value, 0);
    expect(batch.records.last.sets.single, (id: null, value: 60000, reps: 8));
    expect(aiPrompt(time), contains(example));
    expect(aiPrompt(time), contains('UTC+00:00'));
    expect(
      aiPrompt(time),
      contains('Do not reinterpret every historical "today"'),
    );
  });

  test('AI import trends include every entry and preserve weighted reps', () {
    final firstDay = CalendarDay.parse('2026-11-10');
    final lastDay = CalendarDay.parse('2026-11-12');
    final batch = ActivityBatch([
      ActivityRecord(lastDay, 'Push-ups', Measurement.repetitions, [
        (id: null, value: 18, reps: null),
      ], null),
      ActivityRecord(firstDay, 'Bench press', Measurement.weightAndReps, [
        (id: null, value: 60000, reps: 8),
        (id: null, value: 65000, reps: 6),
      ], null),
      ActivityRecord(firstDay, 'Push-ups', Measurement.repetitions, [
        (id: null, value: 10, reps: null),
        (id: null, value: 12, reps: null),
      ], null),
      ActivityRecord(lastDay, 'Push-ups', Measurement.repetitions, [
        (id: null, value: 14, reps: null),
      ], null),
    ]);
    final trends = activityTrends(batch);
    final pushUps = trends[activityKey('Push-ups', Measurement.repetitions)]!;

    expect(pushUps.recordCount, 3);
    expect(pushUps.days, [
      (
        day: firstDay,
        first: 10,
        latest: 12,
        best: 12,
        total: 22,
        count: 2,
        latestReps: null,
        bestReps: null,
        totalReps: null,
      ),
      (
        day: lastDay,
        first: 18,
        latest: 14,
        best: 18,
        total: 32,
        count: 2,
        latestReps: null,
        bestReps: null,
        totalReps: null,
      ),
    ]);
    final bench =
        trends[activityKey('Bench press', Measurement.weightAndReps)]!;
    expect(bench.days.single.latestReps, 6);
    expect(bench.days.single.bestReps, 6);
    expect(bench.days.single.totalReps, 14);
    expect(bench.latestSet, (id: null, value: 65000, reps: 6));
  });

  test('canonical receipts ignore JSON order and name spacing but preserve set order', () {
    final example = activityExample(today);
    final canonical = ActivityBatch(
      decodeActivity(example, today).records.take(2),
    );
    final same = decodeActivity('''{"records":[
      {"notes":null,"sets":[22,20,18],"exercise":{"measurement":"repetitions","name":"  PUSH-UPS "},"date":"2026-11-12"},
      {"notes":null,"sets":[100,90],"exercise":{"measurement":"duration","name":"Plank"},"date":"2026-11-12"}],
      "schemaVersion":1,"format":"fitness-activity-import"}''', today);
    expect(same.fingerprint, canonical.fingerprint);
    expect(
      ActivityBatch(
        decodeActivity(
          example.replaceFirst('22,\n        20', '20,\n        22'),
          today,
        ).records.take(2),
      ).fingerprint,
      isNot(canonical.fingerprint),
    );
  });

  test('AI import rejects future dates, noninteger sets, unknown fields and future schema', () {
    final example = activityExample(today);
    for (final invalid in [
      example.replaceFirst(today.iso, '2026-11-13'),
      example.replaceFirst('22', '22.1'),
      example.replaceFirst('22', '-1'),
      example.replaceFirst('"notes"', '"best"'),
      example.replaceFirst('"schemaVersion": 2', '"schemaVersion": 3'),
    ]) {
      expect(() => decodeActivity(invalid, today), throwsFormatException);
    }
  });

  test('mapping requires explicit archived and mismatched unit decisions; flags overlaps', () {
    final batch = ActivityBatch(
      decodeActivity(activityExample(today), today).records.take(2),
    );
    final archived = exercise(
      'push',
      'Push-ups',
      Measurement.repetitions,
      archived: true,
    );
    final mismatched = exercise('plank', 'Plank', Measurement.repetitions);
    final current = data(
      exercises: [archived, mismatched],
      entries: [
        entry('prior', 'push', [22, 20, 18]),
      ],
      receipts: {batch.fingerprint: time},
    );
    expect(suggestMappings(batch, current.exercises), isEmpty);
    expect(
      () => planActivity(current, batch, {}),
      throwsA(isA<TrackerException>()),
    );
    final plan = planActivity(current, batch, {
      batch.records.first.key: const MapToExercise('push'),
      batch.records.last.key: const CreateMappedExercise('Timed plank'),
    });
    expect(plan.repeated, isTrue);
    expect(plan.possibleDuplicates, 1);
    expect(plan.write.create.single.name, 'Timed plank');
    expect(plan.write.entries.first.sets.map((s) => s.value), [22, 20, 18]);
    expect(archived.archived, isTrue);
  });

  test('merge preserves similar distinct activities and skips unresolved references', () {
    final push = exercise('push', 'Push-ups', Measurement.repetitions);
    final local = data(
      exercises: [push],
      entries: [
        entry('local', 'push', [8], order: 4),
      ],
    );
    final same = data(
      exercises: [push],
      entries: [
        entry('remote', 'push', [8]),
      ],
    );
    final plan = planBackup(local, same, RestoreMode.merge);
    expect(plan.duplicates, 1);
    expect(plan.possibleDuplicates, 1);
    expect(plan.write.data.entries.single.order, 5);
    final conflict = data(
      exercises: [exercise('other', 'Push-ups', Measurement.duration)],
      entries: [
        entry('remote', 'other', [8]),
      ],
    );
    final reject = planBackup(local, conflict, RestoreMode.merge);
    expect(reject.conflicts, hasLength(2));
    expect(reject.write.data.entries, isEmpty);
  });

  test(
    'custom exercise order survives backup replace and merges new exercises',
    () {
      final push = exercise('push', 'Push-ups', Measurement.repetitions);
      final plank = exercise('plank', 'Plank', Measurement.duration);
      final squat = exercise('squat', 'Squat', Measurement.repetitions);
      final custom = (
        appearance: Appearance.dark,
        duration: DurationStyle.seconds,
        haptics: false,
        overviewExerciseOrder: ['plank', 'push'],
      );
      final local = data(exercises: [push, plank], preferences: custom);
      final encoded = encodeBackup(local, time);
      expect(jsonDecode(encoded)['schemaVersion'], exerciseOrderBackupVersion);
      final decoded = decodeBackup(encoded, today);
      expect(decoded.preferences.overviewExerciseOrder, ['plank', 'push']);
      expect(
        planBackup(
          data(),
          decoded,
          RestoreMode.replace,
        ).write.data.preferences.overviewExerciseOrder,
        ['plank', 'push'],
      );

      final incoming = data(
        exercises: [squat, push],
        preferences: (
          appearance: Appearance.system,
          duration: DurationStyle.clock,
          haptics: true,
          overviewExerciseOrder: ['squat', 'push'],
        ),
      );
      final merged = planBackup(local, incoming, RestoreMode.merge);
      expect(merged.write.data.preferences.overviewExerciseOrder, [
        'plank',
        'push',
        'squat',
      ]);
      expect(
        planBackup(
          data(exercises: [push]),
          incoming,
          RestoreMode.merge,
        ).write.data.preferences.overviewExerciseOrder,
        isEmpty,
      );

      final malformed = jsonDecode(encoded) as Map<String, dynamic>;
      malformed['settings']['overviewExerciseOrder'] = ['plank', 'missing'];
      expect(
        () => decodeBackup(jsonEncode(malformed), today),
        throwsFormatException,
      );
    },
  );

  test('backup rejects invalid references, sparse positions and unsupported versions', () {
    final x = exercise('push', 'Push-ups', Measurement.repetitions);
    final backup = encodeBackup(
      data(
        exercises: [x],
        entries: [
          entry('record', x.id, [9, 7]),
        ],
      ),
      time,
    );
    final decoded = jsonDecode(backup) as Map<String, dynamic>;
    expect(decoded['format'], backupFormat);
    for (final invalid in [
      backup.replaceFirst('"exerciseId": "push"', '"exerciseId": "missing"'),
      backup.replaceFirst('"position": 1', '"position": 2'),
      backup.replaceFirst('"schemaVersion": 1', '"schemaVersion": 3'),
      backup.replaceFirst('"position": 1', '"position": 0'),
    ]) {
      expect(() => decodeBackup(invalid, today), throwsFormatException);
    }
  });

  test('v2 validates weigh-ins and merges by measurement date', () {
    final older = (day: today.plusDays(-3), grams: 81250);
    final sameDate = (day: today, grams: 80000);
    final local = data(
      body: BodyData(
        (
          displayName: 'Sam',
          heightMillimeters: null,
          heightUnit: HeightUnit.ftIn,
          weightUnit: WeightUnit.lb,
        ),
        [(day: today, grams: 80125)],
      ),
    );
    final incoming = data(
      body: BodyData(
        (
          displayName: 'Sami',
          heightMillimeters: 1790,
          heightUnit: HeightUnit.cm,
          weightUnit: WeightUnit.kg,
        ),
        [older, sameDate],
      ),
    );
    final json = encodeBackup(incoming, time);
    final parsed = decodeBackup(json, today);
    expect(parsed.body!.profile.heightUnit, HeightUnit.cm);
    final plan = planBackup(local, parsed, RestoreMode.merge);
    expect(plan.write.data.body!.profile, (
      displayName: 'Sam',
      heightMillimeters: 1790,
      heightUnit: HeightUnit.ftIn,
      weightUnit: WeightUnit.lb,
    ));
    expect(plan.write.data.body!.weighIns, [older]);
    expect(plan.conflicts, hasLength(2));
    for (final invalid in [
      json.replaceFirst(older.day.iso, sameDate.day.iso),
      json.replaceFirst('"grams": 81250', '"grams": 0'),
      json.replaceFirst('"heightMillimeters": 1790', '"heightMillimeters": -1'),
      json.replaceFirst('"weightUnit": "kg"', '"weightUnit": "oz"'),
    ]) {
      expect(() => decodeBackup(invalid, today), throwsFormatException);
    }
  });

  test('CSV uses real seconds and protects spreadsheet cells', () {
    final x = exercise('x', '=exercise', Measurement.duration);
    final csv = encodeCsv(
      data(
        exercises: [x],
        entries: [
          entry('id', x.id, [90], notes: '  +formula, "é"\nmore'),
        ],
      ),
    );
    expect(
      csv,
      contains('2026-11-12,"\'=exercise",duration,seconds,"id","id-0",1,90,'),
    );
    expect(csv, contains('"\'  +formula, ""é""\nmore"'));
    expect(csv, endsWith('\r\n'));
  });
}
