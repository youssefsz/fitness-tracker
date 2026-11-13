import 'dart:io';

import 'package:drift/native.dart';
import 'package:fitness_tracker/core/database/database.dart'
    show TrackerDatabase;
import 'package:fitness_tracker/core/database/tracker_repository.dart';
import 'package:fitness_tracker/features/data_transfer/import_plan.dart';
import 'package:fitness_tracker/features/data_transfer/transfer_codec.dart';
import 'package:fitness_tracker/shared/domain/training.dart';

import 'demo_data.dart';

Future<void> main(List<String> args) async {
  if (args.length != 3) {
    stderr.writeln(
      'Usage: dart run tool/seed_simulator_data.dart YYYY-MM-DD SIMULATOR_DATABASE BACKUP_JSON',
    );
    exitCode = 64;
    return;
  }
  final today = CalendarDay.parse(args[0]);
  final database = File(args[1]);
  final backup = File(args[2]);
  final data = demoData(today);
  final exportedAt = DateTime.now().toUtc();
  final text = encodeBackup(data, exportedAt);
  final validated = decodeBackup(text, today);

  await database.parent.create(recursive: true);
  final repo = TrackerRepository(
    TrackerDatabase(NativeDatabase(database)),
    now: () => today.local,
  );
  try {
    final local = await repo.snapshot();
    if (local.exercises.any((x) => x.id.startsWith('v-demo-'))) {
      stdout.writeln(
        'Demo data is already installed. Existing simulator edits were kept.',
      );
      return;
    }
    if (local.exercises.isNotEmpty || local.entries.isNotEmpty) {
      throw StateError(
        'The target already has other data. Nothing was overwritten. Import the demo backup manually if desired.',
      );
    }
    await backup.parent.create(recursive: true);
    await backup.writeAsString(text, flush: true);
    await repo.restore(
      (current) => planBackup(current, validated, RestoreMode.merge).write,
    );
    final saved = await repo.snapshot();
    final sets = saved.entries.fold(
      0,
      (total, entry) => total + entry.sets.length,
    );
    stdout.writeln(
      'Verified ${saved.exercises.length} exercises, ${saved.entries.length} entries, $sets sets and ${saved.goals.length} goals.',
    );
  } finally {
    await repo.close();
  }
}
