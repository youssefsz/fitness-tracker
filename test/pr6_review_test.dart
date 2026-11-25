import 'package:drift/native.dart';
import 'package:fitness_tracker/app/providers.dart';
import 'package:fitness_tracker/app/theme.dart';
import 'package:fitness_tracker/core/database/database.dart'
    show TrackerDatabase;
import 'package:fitness_tracker/core/database/tracker_repository.dart';
import 'package:fitness_tracker/features/data_transfer/import_plan.dart';
import 'package:fitness_tracker/features/data_transfer/transfer_codec.dart';
import 'package:fitness_tracker/features/overview/overview_page.dart';
import 'package:fitness_tracker/shared/domain/training.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../tool/demo_data.dart';

void main() {
  for (final count in [5, 14]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'PR6: pinned reset stays stable with $count rows and ${scale}x text',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(320, 740);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final now = DateTime(2026, 11, 18, 12);
          final repo = TrackerRepository(
            TrackerDatabase(NativeDatabase.memory()),
            now: () => now,
          );
          final fixture = demoData(CalendarDay.fromDate(now));
          await repo.restore(
            (current) => planBackup(current, fixture, RestoreMode.merge).write,
          );
          if (count == 14) {
            await repo.setArchived('v-demo-hollow', false);
            for (var i = 0; i < 8; i++) {
              final exercise = await repo.createExercise(
                'Extra exercise ${i + 1}',
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
          }
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                repositoryProvider.overrideWithValue(repo),
                nowProvider.overrideWithValue(() => now),
              ],
              child: MaterialApp(
                theme: trackerTheme(Brightness.light),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: true,
                  ),
                  child: child!,
                ),
                home: const OverviewPage(),
              ),
            ),
          );
          try {
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.tap(find.byTooltip('Exercise options'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Reorder exercises'));
            await tester.pumpAndSettle();
            expect(find.text('Done').hitTestable(), findsOneWidget);
            expect(find.text('Cancel').hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
            final footer = find.byKey(const ValueKey('exercise-order-footer'));
            final list = find.byKey(const ValueKey('exercise-order-list'));
            await tester.scrollUntilVisible(
              find.byTooltip('Reorder Plank'),
              100,
              scrollable: find.descendant(
                of: list,
                matching: find.byType(Scrollable),
              ),
            );
            await tester.pumpAndSettle();
            final press = find.byKey(
              const ValueKey('reorder-press-v-demo-plank'),
            );
            final touch = await tester.startGesture(
              tester.getCenter(find.byTooltip('Reorder Plank')) -
                  const Offset(60, 0),
            );
            await tester.pump();
            expect(
              (tester.widget<DecoratedBox>(press).decoration as BoxDecoration)
                  .color,
              isNot(Colors.transparent),
            );
            await touch.moveBy(const Offset(0, -50));
            await tester.pumpAndSettle();
            expect(
              (tester.widget<DecoratedBox>(press).decoration as BoxDecoration)
                  .color,
              Colors.transparent,
            );
            await touch.up();
            await tester.pumpAndSettle();
            await tester.ensureVisible(find.byTooltip('Reorder Plank'));
            await tester.pumpAndSettle();
            final footerRect = tester.getRect(footer);
            final listRect = tester.getRect(list);
            final doneRect = tester.getRect(find.text('Done'));
            await tester.tap(find.byTooltip('Reorder Plank'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Move to bottom'));
            await tester.pumpAndSettle();
            expect(tester.getRect(footer), footerRect);
            expect(tester.getRect(list), listRect);
            expect(tester.getRect(find.text('Done')), doneRect);
            expect(find.text('Use recent order').hitTestable(), findsOneWidget);
            await tester.drag(list, const Offset(0, -2000));
            await tester.pumpAndSettle();
            expect(tester.getRect(footer), footerRect);
            expect(find.text('Use recent order').hitTestable(), findsOneWidget);
            await tester.tap(find.text('Use recent order'));
            await tester.pumpAndSettle();
            expect(tester.getRect(footer), footerRect);
            expect(tester.getRect(list), listRect);
            expect(tester.getRect(find.text('Done')), doneRect);
            expect(
              find.text('Recent activity order').hitTestable(),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
            await tester.tap(find.text('Done'));
            await tester.pumpAndSettle();
            expect(find.byTooltip('Exercise options'), findsOneWidget);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            await repo.close();
          }
        },
      );
    }
  }

  test('PR6: backup remains restorable after merging a new exercise', () async {
    final now = DateTime(2026, 11, 18, 12);
    final today = CalendarDay.fromDate(now);
    TrackerRepository open() => TrackerRepository(
      TrackerDatabase(NativeDatabase.memory()),
      now: () => now,
    );
    final local = open();
    final incoming = open();
    addTearDown(local.close);
    addTearDown(incoming.close);
    final push = await local.createExercise(
      'Push-ups',
      Measurement.repetitions,
    );
    final plank = await local.createExercise('Plank', Measurement.duration);
    await local.log([
      EntryDraft(
        exerciseId: push.id,
        day: today,
        sets: [(id: null, value: 12, reps: null)],
      ),
      EntryDraft(
        exerciseId: plank.id,
        day: today,
        sets: [(id: null, value: 60, reps: null)],
      ),
    ]);
    await local.saveOverviewExerciseOrder([plank.id, push.id]);
    await incoming.createExercise('Squats', Measurement.repetitions);
    final source = await incoming.snapshot();
    await local.restore(
      (current) => planBackup(current, source, RestoreMode.merge).write,
    );
    final saved = await local.snapshot();
    expect(saved.exercises, hasLength(3));
    expect(
      () => decodeBackup(encodeBackup(saved, now), today),
      returnsNormally,
    );
  });
}
