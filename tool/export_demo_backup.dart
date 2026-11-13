import 'dart:io';

import 'package:fitness_tracker/features/data_transfer/transfer_codec.dart';
import 'package:fitness_tracker/shared/domain/training.dart';

import 'demo_data.dart';

Future<void> main(List<String> args) async {
  if (args.length > 1) {
    stderr.writeln(
      'Usage: dart run tool/export_demo_backup.dart [OUTPUT_JSON]',
    );
    exitCode = 64;
    return;
  }

  final output = File(args.singleOrNull ?? 'build/qa/v-demo-data.json');
  final now = DateTime.now();
  final today = CalendarDay.fromDate(now);
  final backup = encodeBackup(demoData(today), now);
  await output.parent.create(recursive: true);
  await output.writeAsString(backup);
  stdout.writeln('Wrote fictional workouts to ${output.path}');
}
