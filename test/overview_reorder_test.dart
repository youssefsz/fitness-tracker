import 'dart:async';

import 'package:drift/native.dart';
import 'package:fitness_tracker/app/providers.dart';
import 'package:fitness_tracker/core/database/database.dart'
    show TrackerDatabase;
import 'package:fitness_tracker/core/database/tracker_repository.dart';
import 'package:fitness_tracker/app/theme.dart';
import 'package:fitness_tracker/features/overview/overview_page.dart';
import 'package:fitness_tracker/shared/domain/training.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout, kPressTimeout;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/semantics.dart'
    show CustomSemanticsAction, SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

final _now = DateTime(2026, 11, 18, 12);

class _DeferredOrderRepository extends TrackerRepository {
  _DeferredOrderRepository()
    : super(TrackerDatabase(NativeDatabase.memory()), now: () => _now);

  final release = Completer<void>();
  bool fail = true;
  int saves = 0;

  @override
  Future<void> saveOverviewExerciseOrder(List<String> visibleOrder) async {
    saves++;
    await release.future;
    if (fail) {
      throw const TrackerException('Couldn’t save the order. Try again.');
    }
    await super.saveOverviewExerciseOrder(visibleOrder);
  }
}

Future<void> _openOrdering(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Exercise options'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Reorder exercises'));
  await tester.pumpAndSettle();
}

void main() {
  for (final enabled in [true, false]) {
    for (final reducedMotion in [true, false]) {
      for (final brightness in Brightness.values) {
        testWidgets(
          'touch and pickup feedback: haptics=$enabled, reducedMotion=$reducedMotion, $brightness',
          (tester) async {
            final repo = TrackerRepository(
              TrackerDatabase(NativeDatabase.memory()),
              now: () => _now,
            );
            final first = await repo.createExercise(
              'Push-ups',
              Measurement.repetitions,
            );
            final second = await repo.createExercise(
              'Squats',
              Measurement.repetitions,
            );
            await repo.log([
              EntryDraft(
                exerciseId: first.id,
                day: CalendarDay.parse('2026-11-18'),
                sets: [(id: null, value: 12, reps: null)],
              ),
              EntryDraft(
                exerciseId: second.id,
                day: CalendarDay.parse('2026-11-17'),
                sets: [(id: null, value: 20, reps: null)],
              ),
            ]);
            await repo.savePreferences((
              appearance: Appearance.system,
              duration: DurationStyle.clock,
              haptics: enabled,
              overviewExerciseOrder: <String>[],
            ));
            final pulses = <Object?>[];
            tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              SystemChannels.platform,
              (call) async {
                if (call.method == 'HapticFeedback.vibrate') {
                  pulses.add(call.arguments);
                }
                return null;
              },
            );
            addTearDown(
              () => tester.binding.defaultBinaryMessenger
                  .setMockMethodCallHandler(SystemChannels.platform, null),
            );
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = const Size(402, 874);
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            try {
              await tester.pumpWidget(
                ProviderScope(
                  overrides: [
                    repositoryProvider.overrideWithValue(repo),
                    nowProvider.overrideWithValue(() => _now),
                  ],
                  child: MaterialApp(
                    theme: trackerTheme(brightness),
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(disableAnimations: reducedMotion),
                      child: child!,
                    ),
                    home: const OverviewPage(),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              await _openOrdering(tester);
              final row = find.byKey(ValueKey(first.id));
              final rowRect = tester.getRect(row);
              final press = find.byKey(ValueKey('reorder-press-${first.id}'));
              Color? pressColor() =>
                  (tester.widget<DecoratedBox>(press).decoration
                          as BoxDecoration)
                      .color;
              expect(pressColor(), Colors.transparent);
              final cancelled = await tester.startGesture(
                tester.getCenter(find.text('Push-ups').hitTestable()),
              );
              await tester.pump();
              final touchColor = pressColor()!;
              expect(touchColor, isNot(Colors.transparent));
              expect(touchColor.r, touchColor.g);
              expect(touchColor.g, touchColor.b);
              expect(tester.getRect(row), rowRect);
              expect(pulses, isEmpty);
              await cancelled.cancel();
              await tester.pump();
              expect(pressColor(), Colors.transparent);
              // A tap and a hold shorter than the recognition threshold are not pickup.
              await tester.tap(find.text('Push-ups').hitTestable());
              await tester.pumpAndSettle();
              final gesture = await tester.startGesture(
                tester.getCenter(find.text('Push-ups').hitTestable()),
              );
              await tester.pump();
              expect(pressColor(), touchColor);
              await tester.pump(
                kLongPressTimeout - const Duration(milliseconds: 1),
              );
              final proxy = find.byKey(
                const ValueKey('exercise-order-drag-proxy'),
              );
              expect(proxy, findsNothing);
              expect(pulses, isEmpty);
              await tester.pump(const Duration(milliseconds: 2));
              await tester.pump(const Duration(milliseconds: 16));
              expect(proxy, findsOneWidget);
              expect(
                pulses,
                enabled ? ['HapticFeedbackType.lightImpact'] : isEmpty,
              );
              final pickedUp = tester.widget<Material>(proxy);
              final tint = pickedUp.color!;
              expect(tint.g, greaterThan(tint.r));
              expect(tint.g, greaterThan(tint.b));
              expect(pickedUp.elevation, reducedMotion ? 0 : greaterThan(0));
              final colors = brightness == Brightness.light
                  ? TrackerColors.light
                  : TrackerColors.dark;
              final handle = tester.widget<Icon>(
                find.descendant(
                  of: proxy,
                  matching: find.byIcon(Icons.drag_handle),
                ),
              );
              expect(handle.color, colors.green);
              await gesture.moveBy(const Offset(0, 60));
              await tester.pump(const Duration(milliseconds: 250));
              expect(tester.widget<Material>(proxy).color, tint);
              expect(
                pulses,
                enabled ? ['HapticFeedbackType.lightImpact'] : isEmpty,
              );
              await gesture.up();
              await tester.pumpAndSettle();
              expect(proxy, findsNothing);
              expect(pressColor(), Colors.transparent);
              for (final icon in tester.widgetList<Icon>(
                find.byIcon(Icons.drag_handle),
              )) {
                expect(icon.color, colors.muted);
              }
              expect(
                pulses,
                enabled ? ['HapticFeedbackType.lightImpact'] : isEmpty,
              );
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
  }
  testWidgets('tap moves, save retry, and reset keep the draft until Done', (
    tester,
  ) async {
    final repo = _DeferredOrderRepository();
    final first = await repo.createExercise(
      'Push-ups',
      Measurement.repetitions,
    );
    final second = await repo.createExercise('Squats', Measurement.repetitions);
    await repo.log([
      EntryDraft(
        exerciseId: first.id,
        day: CalendarDay.parse('2026-11-18'),
        sets: [(id: null, value: 12, reps: null)],
      ),
      EntryDraft(
        exerciseId: second.id,
        day: CalendarDay.parse('2026-11-17'),
        sets: [(id: null, value: 20, reps: null)],
      ),
    ]);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(402, 874);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repo),
            nowProvider.overrideWithValue(() => _now),
          ],
          child: MaterialApp(
            theme: trackerTheme(Brightness.light),
            home: const OverviewPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openOrdering(tester);
      final footer = find.byKey(const ValueKey('exercise-order-footer'));
      final recentFooterRect = tester.getRect(footer);
      final doneRect = tester.getRect(find.text('Done'));
      await tester.tap(find.byKey(ValueKey('reorder-handle-${second.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to top'));
      await tester.pumpAndSettle();
      expect(tester.getRect(footer), recentFooterRect);
      expect(tester.getRect(find.text('Done')), doneRect);
      final top = tester.getTopLeft(find.byKey(ValueKey(second.id)));
      expect(
        (await repo.snapshot()).preferences.overviewExerciseOrder,
        isEmpty,
      );
      await tester.tap(find.text('Done'));
      await tester.tap(find.text('Done'));
      await tester.pump();
      expect(find.text('Saving…'), findsOneWidget);
      final cancel = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Cancel'),
      );
      expect(cancel.onPressed, isNull);
      expect(repo.saves, 1);
      expect(tester.getTopLeft(find.byKey(ValueKey(second.id))), top);
      repo.release.complete();
      await tester.pumpAndSettle();
      expect(find.text('Couldn’t save the order. Try again.'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(ValueKey(second.id))).dy,
        lessThan(tester.getTopLeft(find.byKey(ValueKey(first.id))).dy),
      );
      repo.fail = false;
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      final expected = [second.id, first.id];
      expect(
        (await repo.snapshot()).preferences.overviewExerciseOrder,
        expected,
      );
      await _openOrdering(tester);
      await tester.tap(find.text('Use recent order'));
      await tester.pumpAndSettle();
      expect(
        (await repo.snapshot()).preferences.overviewExerciseOrder,
        expected,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        (await repo.snapshot()).preferences.overviewExerciseOrder,
        expected,
      );
      await _openOrdering(tester);
      await tester.tap(find.text('Use recent order'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(
        (await repo.snapshot()).preferences.overviewExerciseOrder,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    } finally {
      if (!repo.release.isCompleted) repo.release.complete();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await repo.close();
    }
  });

  for (final dragFrom in ['label', 'padding', 'handle']) {
    testWidgets('dragging from $dragFrom saves the chosen order', (
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
      final squats = await repo.createExercise(
        'Squats',
        Measurement.repetitions,
      );
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

        expect(find.byTooltip('Exercise options'), findsOneWidget);
        expect(find.byTooltip('Reorder Push-ups'), findsNothing);
        final handleKey = ValueKey('reorder-handle-${pushups.id}');
        expect(find.byKey(handleKey), findsNothing);
        expect(
          tester.getTopLeft(find.text('Push-ups').first).dy,
          lessThan(tester.getTopLeft(find.text('Squats').first).dy),
        );

        await tester.tap(find.byTooltip('Exercise options'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reorder exercises'));
        await tester.pumpAndSettle();
        expect(find.text('Done'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.byKey(handleKey), findsOneWidget);
        expect(find.byTooltip('Reorder Push-ups'), findsOneWidget);

        final row = find.byKey(ValueKey(pushups.id));
        final rowRect = tester.getRect(row);
        final start = switch (dragFrom) {
          'label' => tester.getCenter(find.text('Push-ups').hitTestable()),
          'padding' => rowRect.topLeft + const Offset(2, 2),
          _ => tester.getCenter(find.byKey(handleKey)),
        };
        final next = tester.getBottomLeft(find.byKey(ValueKey(squats.id)));
        final target = Offset(start.dx, next.dy + 20);
        final drag = await tester.startGesture(start);
        await tester.pump(kLongPressTimeout + kPressTimeout);
        await drag.moveTo(start + const Offset(0, 60));
        await tester.pump(const Duration(milliseconds: 250));
        final proxy = find.byKey(const ValueKey('exercise-order-drag-proxy'));
        expect(proxy, findsOneWidget);
        expect(
          find.descendant(of: proxy, matching: find.byType(Divider)),
          findsNothing,
        );
        expect(tester.getSize(proxy).height, closeTo(rowRect.height - 1, .01));
        expect(tester.getSize(proxy).width, rowRect.width);
        final proxyRect = tester.getRect(proxy);
        final proxyLabel = tester.getRect(
          find.descendant(of: proxy, matching: find.text('Push-ups')),
        );
        final latest = tester.getRect(
          find.descendant(of: proxy, matching: find.text('Latest 12 reps')),
        );
        expect(proxyLabel.top - proxyRect.top, greaterThanOrEqualTo(Space.md));
        expect(
          proxyLabel.top - proxyRect.top,
          closeTo(proxyRect.bottom - latest.bottom, .01),
        );
        await drag.moveTo(target);
        await tester.pump(kPressTimeout);
        await drag.up();
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(find.byKey(ValueKey(squats.id))).dy,
          lessThan(tester.getTopLeft(find.byKey(ValueKey(pushups.id))).dy),
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
          tester.getTopLeft(find.byKey(ValueKey(pushups.id))).dy,
          lessThan(tester.getTopLeft(find.byKey(ValueKey(squats.id))).dy),
        );
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(
          (await repo.snapshot()).preferences.overviewExerciseOrder,
          isEmpty,
        );

        await tester.tap(find.byTooltip('Exercise options'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reorder exercises'));
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
        expect(find.byTooltip('Exercise options'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await repo.close();
      }
    });
  }
}
