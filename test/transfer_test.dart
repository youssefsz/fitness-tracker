import 'dart:convert';

import 'package:fitness_tracker/features/data_transfer/import_plan.dart';
import 'package:fitness_tracker/features/data_transfer/transfer_codec.dart';
import 'package:fitness_tracker/shared/domain/training.dart';
import 'package:flutter_test/flutter_test.dart';

final today = CalendarDay.parse('2026-11-12');
final time = DateTime.utc(2026, 11, 12, 14);
BackupData data({
  List<Exercise> exercises = const [],
  List<Entry> entries = const [],
  Map<String, DateTime> receipts = const {},
}) => BackupData(
  exercises: exercises,
  entries: entries,
  goals: [],
  preferences: defaultPreferences,
  receipts: receipts,
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
      (id: '$id-$i', position: i, value: value),
  ],
);

void main() {
  test('AI example and copied prompt share the validated contract', () {
    final example = activityExample(today);
    final batch = decodeActivity(example, today);
    expect(batch.records.first.sets, [22, 20, 18]);
    expect(batch.records.last.sets, [100, 90]);
    expect(aiPrompt(time), contains(example));
    expect(aiPrompt(time), contains('UTC+00:00'));
    expect(
      aiPrompt(time),
      contains('Do not reinterpret every historical "today"'),
    );
  });

  test('canonical receipts ignore JSON order and name spacing but preserve set order', () {
    final example = activityExample(today);
    final canonical = decodeActivity(example, today);
    final same = decodeActivity('''{"records":[
      {"notes":null,"sets":[22,20,18],"exercise":{"measurement":"repetitions","name":"  PUSH-UPS "},"date":"2026-11-12"},
      {"notes":null,"sets":[100,90],"exercise":{"measurement":"duration","name":"Plank"},"date":"2026-11-12"}],
      "schemaVersion":1,"format":"fitness-activity-import"}''', today);
    expect(same.fingerprint, canonical.fingerprint);
    expect(
      decodeActivity(
        example.replaceFirst('22,\n        20', '20,\n        22'),
        today,
      ).fingerprint,
      isNot(canonical.fingerprint),
    );
  });

  test('AI import rejects future dates, noninteger sets, unknown fields and future schema', () {
    final example = activityExample(today);
    for (final invalid in [
      example.replaceFirst(today.iso, '2026-11-13'),
      example.replaceFirst('22', '22.1'),
      example.replaceFirst('22', '0'),
      example.replaceFirst('"notes"', '"best"'),
      example.replaceFirst('"schemaVersion": 1', '"schemaVersion": 2'),
    ]) {
      expect(() => decodeActivity(invalid, today), throwsFormatException);
    }
  });

  test('mapping requires explicit archived and mismatched unit decisions; flags overlaps', () {
    final batch = decodeActivity(activityExample(today), today);
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
      backup.replaceFirst('"schemaVersion": 1', '"schemaVersion": 2'),
      backup.replaceFirst('"position": 1', '"position": 0'),
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
