import 'dart:convert';
import 'dart:math' as math;

import '../../shared/domain/training.dart';
import 'transfer_codec.dart';

enum RestoreMode { merge, replace }

class BackupPlan {
  BackupPlan(
    this.write,
    this.duplicates,
    this.possibleDuplicates,
    Iterable<String> conflicts,
  ) : conflicts = List.unmodifiable(conflicts);
  final BackupWrite write;
  final int duplicates;
  final int possibleDuplicates;
  final List<String> conflicts;
}

String _activitySignature(String id, CalendarDay day, Iterable<int> values) =>
    jsonEncode([id, day.iso, values.toList()]);

BackupPlan planBackup(BackupData current, BackupData source, RestoreMode mode) {
  if (mode == RestoreMode.replace) {
    return BackupPlan((data: source, replace: true), 0, 0, []);
  }
  final byId = {for (final x in current.exercises) x.id: x};
  final byName = {for (final x in current.exercises) normalizeName(x.name): x};
  final localEntries = {for (final e in current.entries) e.id: e};
  final localSets = {
    for (final e in current.entries)
      for (final s in e.sets) s.id,
  };
  final localGoals = {for (final g in current.goals) g.exerciseId: g};
  final signatures = {
    for (final e in current.entries)
      _activitySignature(
        normalizeName(byId[e.exerciseId]!.name),
        e.day,
        e.sets.map((s) => s.value),
      ),
  };
  final sourceById = {for (final x in source.exercises) x.id: x};
  final exerciseMap = <String, String>{};
  final exercises = <Exercise>[], entries = <Entry>[], goals = <Goal>[];
  final conflicts = <String>[];
  final receipts = <String, DateTime>{};
  var duplicates = 0, possible = 0;
  var order = current.entries.fold(0, (last, e) => math.max(last, e.order));

  for (final x in source.exercises) {
    final sameId = byId[x.id];
    final sameName = byName[normalizeName(x.name)];
    if (sameId != null) {
      if (exerciseContent(sameId) == exerciseContent(x)) {
        duplicates++;
      } else {
        conflicts.add(
          'Exercise "${x.name}" changed. Keep "${sameId.name}" from this device.',
        );
      }
      if (sameId.measurement == x.measurement) exerciseMap[x.id] = sameId.id;
    } else if (sameName != null) {
      conflicts.add(
        '"${x.name}" uses a different ID. Keep the exercise on this device and skip entries tied to the incoming ID.',
      );
    } else {
      exercises.add(x);
      exerciseMap[x.id] = x.id;
    }
  }
  for (final e
      in (source.entries.toList()
        ..sort((a, b) => a.order.compareTo(b.order)))) {
    final currentEntry = localEntries[e.id];
    final label = '${sourceById[e.exerciseId]!.name} on ${e.day.iso}';
    if (currentEntry != null) {
      if (entryContent(currentEntry) == entryContent(e)) {
        duplicates++;
      } else {
        conflicts.add(
          'Entry for $label changed. Keep the entry on this device.',
        );
      }
      continue;
    }
    final targetId = exerciseMap[e.exerciseId];
    if (targetId == null || e.sets.any((s) => localSets.contains(s.id))) {
      conflicts.add(
        'Skip entry for $label because its exercise or a set ID conflicts.',
      );
      continue;
    }
    if (signatures.contains(
      _activitySignature(
        normalizeName(sourceById[e.exerciseId]!.name),
        e.day,
        e.sets.map((s) => s.value),
      ),
    )) {
      possible++;
    }
    if (order >= maxEntryOrder) {
      throw const TrackerException(
        'This backup exceeds the available entry order range.',
      );
    }
    entries.add(
      Entry(
        id: e.id,
        exerciseId: targetId,
        day: e.day,
        notes: e.notes,
        order: ++order,
        createdAt: e.createdAt,
        updatedAt: e.updatedAt,
        sets: e.sets,
      ),
    );
  }
  for (final goal in source.goals) {
    final local = localGoals[goal.exerciseId];
    final name = sourceById[goal.exerciseId]!.name;
    if (local != null) {
      if (goalContent(local) == goalContent(goal)) {
        duplicates++;
      } else {
        conflicts.add(
          'Goal for "$name" changed. Keep the goal on this device.',
        );
      }
    } else if (exerciseMap.containsKey(goal.exerciseId)) {
      goals.add(goal);
    } else {
      conflicts.add('Skip goal for "$name" because its exercise conflicts.');
    }
  }
  for (final receipt in source.receipts.entries) {
    if (current.receipts.containsKey(receipt.key)) {
      duplicates++;
    } else {
      receipts[receipt.key] = receipt.value;
    }
  }
  return BackupPlan(
    (
      replace: false,
      data: BackupData(
        exercises: exercises,
        entries: entries,
        goals: goals,
        preferences: current.preferences,
        receipts: receipts,
      ),
    ),
    duplicates,
    possible,
    conflicts,
  );
}

sealed class ExerciseMapping {
  const ExerciseMapping();
}

class MapToExercise extends ExerciseMapping {
  const MapToExercise(this.id);
  final String id;
}

class CreateMappedExercise extends ExerciseMapping {
  const CreateMappedExercise(this.name);
  final String name;
}

Map<String, ActivityRecord> activityGroups(ActivityBatch batch) => {
  for (final record in batch.records.reversed) record.key: record,
};

Map<String, ExerciseMapping> suggestMappings(
  ActivityBatch batch,
  Iterable<Exercise> catalog,
) {
  final names = {
    for (final exercise in catalog) normalizeName(exercise.name): exercise,
  };
  final mappings = <String, ExerciseMapping>{};
  for (final group in activityGroups(batch).entries) {
    final record = group.value;
    final same = names[normalizeName(record.name)];
    if (same == null) {
      mappings[group.key] = CreateMappedExercise(record.name);
    } else if (!same.archived && same.measurement == record.measurement) {
      mappings[group.key] = MapToExercise(same.id);
    }
  }
  return mappings;
}

class ActivityPlan {
  const ActivityPlan(this.write, this.repeated, this.possibleDuplicates);
  final ActivityWrite write;
  final bool repeated;
  final int possibleDuplicates;
}

ActivityPlan planActivity(
  BackupData current,
  ActivityBatch batch,
  Map<String, ExerciseMapping> mappings,
) {
  final create = <NewExerciseSpec>[];
  final byId = {for (final x in current.exercises) x.id: x};
  final names = current.exercises.map((x) => normalizeName(x.name)).toSet();
  final targets = <String, String>{};
  for (final group in activityGroups(batch).entries) {
    final record = group.value;
    switch (mappings[group.key]) {
      case MapToExercise(:final id):
        if (byId[id]?.measurement != record.measurement) {
          throw TrackerException(
            'Choose an exercise with the same measurement for "${record.name}".',
          );
        }
        targets[group.key] = id;
      case CreateMappedExercise(:final name):
        if (exerciseNameError(name) case final error?) {
          throw TrackerException('${record.name}: $error');
        }
        if (!names.add(normalizeName(name))) {
          throw TrackerException(
            '"${name.trim()}" is already in use. Choose another name or map to an existing exercise.',
          );
        }
        targets[group.key] = group.key;
        create.add((
          key: group.key,
          name: name.trim(),
          measurement: record.measurement,
        ));
      case null:
        throw TrackerException('Choose a mapping for "${record.name}".');
    }
  }
  final existing = {
    for (final e in current.entries)
      _activitySignature(e.exerciseId, e.day, e.sets.map((s) => s.value)),
  };
  var overlaps = 0;
  final entries = <EntryDraft>[];
  for (final record in batch.records) {
    final id = targets[record.key]!;
    if (existing.contains(_activitySignature(id, record.day, record.sets))) {
      overlaps++;
    }
    entries.add(
      EntryDraft(
        exerciseId: id,
        day: record.day,
        notes: record.notes,
        sets: record.sets.map((v) => (id: null, value: v)),
      ),
    );
  }
  return ActivityPlan(
    (
      create: List.unmodifiable(create),
      entries: List.unmodifiable(entries),
      fingerprint: batch.fingerprint,
    ),
    current.receipts.containsKey(batch.fingerprint),
    overlaps,
  );
}
