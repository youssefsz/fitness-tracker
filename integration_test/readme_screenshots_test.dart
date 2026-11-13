import 'dart:io';

import 'package:drift/native.dart';
import 'package:fitness_tracker/app/providers.dart';
import 'package:fitness_tracker/core/database/database.dart'
    show TrackerDatabase;
import 'package:fitness_tracker/core/database/tracker_repository.dart';
import 'package:fitness_tracker/features/data_transfer/import_plan.dart';
import 'package:fitness_tracker/features/progress/performance_chart.dart';
import 'package:fitness_tracker/main.dart';
import 'package:fitness_tracker/shared/domain/training.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import '../tool/demo_data.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const output = String.fromEnvironment('README_SCREENSHOT_DIR');

  testWidgets('capture the four README screens', skip: output.isEmpty, (
    tester,
  ) async {
    final now = DateTime(2026, 11, 12, 12);
    final fixture = demoData(CalendarDay.fromDate(now));
    final repository = TrackerRepository(
      TrackerDatabase(NativeDatabase.memory()),
      now: () => now,
    );
    tester.testTextInput.register();
    addTearDown(() async {
      tester.testTextInput.unregister();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await repository.close();
    });

    await repository.restore(
      (current) => planBackup(current, fixture, RestoreMode.merge).write,
    );
    await repository.savePreferences((
      appearance: Appearance.light,
      duration: DurationStyle.clock,
      haptics: false,
    ));
    await repository.saveProgressExercise(
      fixture.exercises
          .singleWhere((exercise) => exercise.name == 'Push-ups')
          .id,
    );

    Finder visible(String text) => find.text(text).hitTestable();

    Future<void> capture(String name, Finder ready) async {
      // A frame can settle before the Drift streams have returned their data.
      for (var i = 0; i < 100 && ready.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(ready, findsWidgets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final png = await binding.takeScreenshot(name);
      await File(p.join(output, '$name.png')).writeAsBytes(png);
    }

    Future<void> tap(Finder control) async {
      await tester.tap(control.first);
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repository),
          nowProvider.overrideWithValue(() => now),
        ],
        child: const FitnessApp(),
      ),
    );
    await capture('overview', visible('Push-ups'));
    await tap(visible('Progress'));
    await capture('progress', find.byType(PerformanceChart).hitTestable());
    await tap(visible('History'));
    await capture('history', visible('Plank'));

    await tap(find.byTooltip('Add entry').hitTestable());
    await tap(visible('Push-ups'));
    Future<void> enterReps(String reps) async {
      await tester.enterText(find.byType(TextFormField).first, reps);
      await tester.pumpAndSettle();
    }

    await enterReps('24');
    await tap(visible('Add set'));
    await enterReps('22');
    await tap(visible('Add set'));
    await enterReps('20');
    FocusManager.instance.primaryFocus?.unfocus();
    await capture('log', visible('Save 3 sets'));
  });
}
