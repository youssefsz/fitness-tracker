import 'package:drift/native.dart';
import 'package:fitness_tracker/app/providers.dart';
import 'package:fitness_tracker/core/database/database.dart'
    show TrackerDatabase;
import 'package:fitness_tracker/core/database/tracker_repository.dart';
import 'package:fitness_tracker/app/theme.dart';
import 'package:fitness_tracker/features/overview/overview_page.dart';
import 'package:fitness_tracker/shared/domain/training.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout, kPressTimeout;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/semantics.dart'
    show CustomSemanticsAction, SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

final _now = DateTime(2026, 11, 18, 12);

void main() {
  testWidgets('reordering is explicit and saves the chosen order', (
    tester,
  ) async {
    final repo = TrackerRepository(
      TrackerDatabase(NativeDatabase.memory()),
      now: () => _now,
    );
    final pushups = await repo.createExercise(
      'Push-ups',
      Measurement.repetitions,
    );
    final squats = await repo.createExercise('Squats', Measurement.repetitions);
    await repo.log([
      EntryDraft(
        exerciseId: pushups.id,
        day: CalendarDay.parse('2026-11-18'),
        sets: [(id: null, value: 12, reps: null)],
      ),
      EntryDraft(
        exerciseId: squats.id,
        day: CalendarDay.parse('2026-11-17'),
        sets: [(id: null, value: 20, reps: null)],
      ),
    ]);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(402, 874);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();

    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repo),
            nowProvider.overrideWithValue(() => _now),
          ],
          child: MaterialApp(
            theme: trackerTheme(Brightness.light)
                .copyWith(splashFactory: NoSplash.splashFactory),
            home: const OverviewPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reorder'), findsOneWidget);
      expect(find.bySemanticsLabel('Reorder Push-ups'), findsNothing);
      final handleKey = ValueKey('reorder-handle-${pushups.id}');
      expect(find.byKey(handleKey), findsNothing);
      expect(
        tester.getTopLeft(find.text('Push-ups').first).dy,
        lessThan(tester.getTopLeft(find.text('Squats').first).dy),
      );

      await tester.tap(find.text('Reorder'));
      await tester.pumpAndSettle();
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.byKey(handleKey), findsOneWidget);
      expect(find.bySemanticsLabel('Reorder Push-ups'), findsOneWidget);

      final start = tester.getCenter(find.byKey(handleKey));
      final rowBottom = tester.getBottomLeft(find.byKey(ValueKey(squats.id)));
      final target = rowBottom + const Offset(0, 48);
      final drag = await tester.startGesture(start);
      await tester.pump(kLongPressTimeout + kPressTimeout);
      await drag.moveTo(start + const Offset(0, 100));
      await tester.pump(kPressTimeout);
      await drag.moveTo(target);
      await tester.pump(kPressTimeout);
      await drag.up();
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Squats').first).dy,
        lessThan(tester.getTopLeft(find.text('Push-ups').first).dy),
      );
      expect(
        (await repo.snapshot()).preferences.overviewExerciseOrder,
        isEmpty,
      );

      final moveUp = CustomSemanticsAction(label: 'Move up');
      moveUpNode(String name) => find.semantics.byPredicate((node) {
        final actions = node.getSemanticsData().customSemanticsActionIds;
        return node.label.contains(name) &&
            actions?.contains(CustomSemanticsAction.getIdentifier(moveUp)) ==
                true;
      });
      tester.semantics.performAction(
        moveUpNode('Push-ups'),
        SemanticsAction.customAction,
        args: CustomSemanticsAction.getIdentifier(moveUp),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.text('Push-ups').first).dy,
        lessThan(tester.getTopLeft(find.text('Squats').first).dy),
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        (await repo.snapshot()).preferences.overviewExerciseOrder,
        isEmpty,
      );

      await tester.tap(find.text('Reorder'));
      await tester.pumpAndSettle();
      tester.semantics.performAction(
        moveUpNode('Squats'),
        SemanticsAction.customAction,
        args: CustomSemanticsAction.getIdentifier(moveUp),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect((await repo.snapshot()).preferences.overviewExerciseOrder, [
        squats.id,
        pushups.id,
      ]);
      expect(
        tester.getTopLeft(find.text('Squats').first).dy,
        lessThan(tester.getTopLeft(find.text('Push-ups').first).dy),
      );
      expect(find.text('Reorder'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await repo.close();
    }
  });
}
