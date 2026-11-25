import 'dart:io';

import 'package:drift/native.dart';
import 'package:fitness_tracker/app/providers.dart';
import 'package:fitness_tracker/core/database/database.dart'
    show TrackerDatabase;
import 'package:fitness_tracker/core/database/tracker_repository.dart';
import 'package:fitness_tracker/features/data_transfer/import_plan.dart';
import 'package:fitness_tracker/main.dart';
import 'package:fitness_tracker/shared/domain/training.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout, kPressTimeout;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../tool/demo_data.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'exercise options, drag and tap ordering, cancel, persistence, reset and appearances',
    (tester) async {
      final now = DateTime(2026, 11, 18, 12);
      final directory = await Directory.systemTemp.createTemp(
        'exercise-order-',
      );
      final file = File(p.join(directory.path, 'fitness.sqlite'));
      TrackerRepository open() => TrackerRepository(
        TrackerDatabase(NativeDatabase(file)),
        now: () => now,
      );
      var repo = open();
      final fixture = demoData(CalendarDay.fromDate(now));
      await repo.restore(
        (current) => planBackup(current, fixture, RestoreMode.merge).write,
      );
      await repo.setArchived('v-demo-hollow', false);
      for (final name in [
        'Bench press',
        'Deadlift',
        'Dumbbell rows',
        'Overhead press',
        'Lunges',
        'Burpees',
        'Jump rope',
        'Side plank',
      ]) {
        final exercise = await repo.createExercise(
          name,
          Measurement.repetitions,
        );
        await repo.log([
          EntryDraft(
            exerciseId: exercise.id,
            day: CalendarDay.fromDate(now).plusDays(-20),
            sets: [(id: null, value: 10, reps: null)],
          ),
        ]);
      }
      await repo.savePreferences((
        appearance: Appearance.light,
        duration: DurationStyle.clock,
        haptics: false,
        overviewExerciseOrder: <String>[],
      ));

      Future<void> settle() async {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      Future<void> present() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              repositoryProvider.overrideWithValue(repo),
              nowProvider.overrideWithValue(() => now),
            ],
            child: const FitnessApp(),
          ),
        );
        await settle();
        for (
          var i = 0;
          i < 100 && find.byTooltip('Exercise options').evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(find.byTooltip('Exercise options'), findsOneWidget);
        await settle();
      }

      Future<void> tap(String text) async {
        await tester.tap(find.text(text).hitTestable().first);
        await settle();
      }

      Future<void> options() async {
        await tester.tap(find.byTooltip('Exercise options'));
        await settle();
      }

      Future<void> reorder() async {
        await options();
        await tap('Reorder exercises');
        expect(
          find.byKey(const ValueKey('exercise-order-list')),
          findsOneWidget,
        );
      }

      var converted = false;
      Future<void> capture(String name) async {
        if (!const bool.fromEnvironment('CAPTURE_REORDER_SCREENSHOTS')) return;
        if (Platform.isAndroid && !converted) {
          await binding.convertFlutterSurfaceToImage();
          converted = true;
        }
        await settle();
        for (var i = 0; i < 3; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await binding.takeScreenshot(name);
      }

      try {
        await present();
        await capture('overview-light');
        final ids = (await repo.watchOverview().first).exercises
            .map((x) => x.exerciseId)
            .toList();
        await options();
        await capture('exercise-menu-light');
        await tap('Reorder exercises');
        await capture('reorder-light');
        final footer = find.byKey(const ValueKey('exercise-order-footer'));
        final footerRect = tester.getRect(footer);
        await tester.tap(find.byKey(ValueKey('reorder-handle-${ids[1]}')));
        await settle();
        await capture('move-options-light');
        await tap('Move to top');
        expect(
          tester.getTopLeft(find.byKey(ValueKey(ids[1]))).dy,
          lessThan(tester.getTopLeft(find.byKey(ValueKey(ids[0]))).dy),
        );
        expect(tester.getRect(footer), footerRect);
        expect(find.text('Use recent order').hitTestable(), findsOneWidget);
        await tester.drag(
          find.byKey(const ValueKey('exercise-order-list')),
          const Offset(0, -1800),
        );
        await settle();
        expect(tester.getRect(footer), footerRect);
        expect(find.text('Use recent order').hitTestable(), findsOneWidget);
        await capture('pinned-reset-scrolled');
        expect(
          (await repo.snapshot()).preferences.overviewExerciseOrder,
          isEmpty,
        );
        await tap('Cancel');
        expect(
          (await repo.snapshot()).preferences.overviewExerciseOrder,
          isEmpty,
        );

        await reorder();
        final start =
            tester.getTopLeft(find.byKey(ValueKey(ids.first))) +
            const Offset(70, 30);
        final next = tester.getCenter(find.byKey(ValueKey(ids[1])));
        final gesture = await tester.startGesture(start);
        await tester.pump(const Duration(milliseconds: 16));
        if (const bool.fromEnvironment('CAPTURE_REORDER_SCREENSHOTS')) {
          await binding.takeScreenshot('touch-light');
        }
        await tester.pump(kLongPressTimeout + kPressTimeout);
        await gesture.moveTo(start + const Offset(0, 60));
        await tester.pump(kPressTimeout);
        await gesture.moveTo(Offset(start.dx, next.dy + 8));
        await tester.pump(const Duration(milliseconds: 300));
        await capture('drag-light');
        await gesture.up();
        await settle();
        await tap('Done');
        final expected = [ids[1], ids[0], ...ids.skip(2)];
        expect(
          (await repo.watchOverview().first).exercises.map((x) => x.exerciseId),
          expected,
        );
        await capture('overview-custom-light');
        await tester.pumpWidget(const SizedBox.shrink());
        await settle();
        await repo.close();
        repo = open();
        await present();
        expect(
          (await repo.watchOverview().first).exercises.map((x) => x.exerciseId),
          expected,
        );

        await reorder();
        await tap('Use recent order');
        expect(
          (await repo.snapshot()).preferences.overviewExerciseOrder,
          isNotEmpty,
        );
        await tap('Cancel');
        expect(
          (await repo.watchOverview().first).exercises.map((x) => x.exerciseId),
          expected,
        );
        await reorder();
        await tap('Use recent order');
        await tap('Done');
        expect(
          (await repo.snapshot()).preferences.overviewExerciseOrder,
          isEmpty,
        );
        expect(
          (await repo.watchOverview().first).exercises.map((x) => x.exerciseId),
          ids,
        );
        await options();
        await tap('Exercise library');
        expect(find.text('Exercises').hitTestable(), findsWidgets);
        await tester.binding.handlePopRoute();
        await settle();
        await repo.savePreferences((
          appearance: Appearance.dark,
          duration: DurationStyle.clock,
          haptics: false,
          overviewExerciseOrder: <String>[],
        ));
        await tester.pump(const Duration(milliseconds: 200));
        await settle();
        await capture('overview-dark');
        await reorder();
        await capture('reorder-dark');
        final darkStart =
            tester.getTopLeft(find.byKey(ValueKey(ids.first))) +
            const Offset(70, 30);
        final darkDrag = await tester.startGesture(darkStart);
        await tester.pump(const Duration(milliseconds: 16));
        if (const bool.fromEnvironment('CAPTURE_REORDER_SCREENSHOTS')) {
          await binding.takeScreenshot('touch-dark');
        }
        await tester.pump(kLongPressTimeout + kPressTimeout);
        await darkDrag.moveBy(const Offset(0, 60));
        await tester.pump(const Duration(milliseconds: 250));
        await capture('drag-dark');
        await darkDrag.up();
        await settle();
        await tap('Cancel');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await repo.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
