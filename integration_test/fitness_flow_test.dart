import 'dart:io';

import 'package:drift/native.dart';
import 'package:fitness_tracker/app/providers.dart';
import 'package:fitness_tracker/core/database/database.dart'
    show TrackerDatabase;
import 'package:fitness_tracker/core/database/tracker_repository.dart';
import 'package:fitness_tracker/features/data_transfer/transfer_codec.dart';
import 'package:fitness_tracker/main.dart';
import 'package:fitness_tracker/shared/domain/training.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final _now = DateTime(2026, 11, 12, 12);
final _today = CalendarDay.fromDate(_now);

Finder _visible(String label) => find.text(label).hitTestable();

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 25),
  );
}

Future<void> _reveal(WidgetTester tester, Finder widget) async {
  if (widget.hitTestable().evaluate().isNotEmpty) return;
  final scroll = find.byType(CustomScrollView).hitTestable();
  if (widget.evaluate().isEmpty && scroll.evaluate().isNotEmpty) {
    final scrollable = find
        .descendant(of: scroll.first, matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(
      widget,
      170,
      scrollable: scrollable,
      maxScrolls: 12,
    );
    await _settle(tester);
  }
  if (widget.hitTestable().evaluate().isEmpty && widget.evaluate().isNotEmpty) {
    await Scrollable.ensureVisible(tester.element(widget.last), alignment: .45);
    await _settle(tester);
  }
}

Future<void> _tap(WidgetTester tester, String text) async {
  final widget = find.text(text, skipOffstage: false);
  await _reveal(tester, widget);
  expect(
    _visible(text),
    findsWidgets,
    reason: 'Expected a visible "$text" control.',
  );
  await tester.tap(_visible(text).first);
  await _settle(tester);
}

Future<void> _tooltip(WidgetTester tester, String label) async {
  final widget = find.byTooltip(label, skipOffstage: false);
  await _reveal(tester, widget);
  expect(
    widget.hitTestable(),
    findsWidgets,
    reason: 'Expected a visible "$label" control.',
  );
  await tester.tap(widget.hitTestable().first);
  await _settle(tester);
}

Future<void> _present(WidgetTester tester, TrackerRepository repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        nowProvider.overrideWithValue(() => _now),
      ],
      child: const FitnessApp(),
    ),
  );
  await _settle(tester);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> capture(String name) async {
    final bytes = await binding.takeScreenshot(name);
    const hostPath = String.fromEnvironment('V_QA_PATH');
    final base = await getTemporaryDirectory();
    final directory = Directory(
      hostPath.isEmpty ? p.join(base.path, 'v-integration-captures') : hostPath,
    );
    await directory.create(recursive: true);
    await File(p.join(directory.path, '$name.png')).writeAsBytes(bytes);
  }

  testWidgets(
    'log two exercise types, backdate, compare, edit, goal, archive, reopen and delete',
    (tester) async {
      tester.testTextInput.register();
      addTearDown(tester.testTextInput.unregister);
      final directory = await Directory.systemTemp.createTemp('v-integration-');
      final database = File(p.join(directory.path, 'fitness.sqlite'));
      TrackerRepository open() => TrackerRepository(
        TrackerDatabase(NativeDatabase.createInBackground(database)),
        now: () => _now,
      );
      var repo = open();
      try {
        await _present(tester, repo);
        expect(find.text('Start with one result.'), findsOneWidget);
        await capture('01-empty');

        await _tap(tester, 'History');
        await _tap(tester, '11');
        await _tap(tester, 'Add');
        await _tap(tester, 'Create exercise');
        await tester.enterText(find.byType(TextField).first, 'Push-ups');
        await _tap(tester, 'Create exercise');
        expect(find.text('11 Nov 2026'), findsOneWidget);
        await tester.enterText(find.byType(TextFormField).first, '22');
        await _tap(tester, 'Add set');
        await tester.enterText(find.byType(TextFormField).at(1), '20');
        await _tap(tester, 'Add set');
        await tester.enterText(find.byType(TextFormField).at(2), '18');
        await _tap(tester, 'Add another exercise');
        await _tap(tester, 'Create exercise');
        await tester.enterText(find.byType(TextField).first, 'Plank');
        await _tap(tester, 'Duration');
        await _tap(tester, 'Create exercise');
        await _reveal(
          tester,
          find.widgetWithText(TextFormField, 'Minutes', skipOffstage: false),
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Minutes', skipOffstage: false),
          '1',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Seconds', skipOffstage: false),
          '40',
        );
        await _tap(tester, 'Save 4 sets');
        expect(find.text('Latest 18 reps · Best 22 reps'), findsOneWidget);
        expect(find.text('Latest 1:40 · Best 1:40'), findsOneWidget);
        await capture('02-history');

        final recorded = await repo.snapshot();
        expect(recorded.entries, hasLength(2));
        expect(recorded.entries.map((e) => e.day).toSet(), {
          _today.plusDays(-1),
        });
        await _tap(tester, 'Overview');
        expect(find.text('18 reps'), findsWidgets);
        await capture('03-overview');
        await _tap(tester, 'Progress');
        await _tap(tester, 'Plank');
        await _tap(tester, 'Push-ups');
        await _tap(tester, 'Best set');
        expect(find.textContaining('22 reps'), findsWidgets);
        await _tap(tester, 'View values');
        expect(find.text('Best set by date'), findsOneWidget);
        await _tap(tester, '11 Nov 2026');
        await _tap(tester, 'All time');
        await _tap(tester, 'Last 7 days');
        await _tap(tester, 'Apply range');
        expect(find.text('Last 7 days'), findsOneWidget);
        await capture('04-progress');

        await _tap(tester, 'History');
        await _tooltip(tester, 'Options for Push-ups on 11 Nov 2026');
        await _tap(tester, 'Edit entry');
        await tester.enterText(find.byType(TextFormField).first, '24');
        await _tap(tester, 'Save changes');
        expect(find.text('Latest 18 reps · Best 24 reps'), findsOneWidget);
        await _tap(tester, 'Overview');
        await _tap(tester, 'Push-ups');
        await _tap(tester, 'Set goal');
        await tester.enterText(find.byType(TextField).first, '24');
        await _tap(tester, 'Save goal');
        expect(find.text('Achieved'), findsOneWidget);
        await _tap(tester, 'Edit goal');
        await tester.enterText(find.byType(TextField).first, '25');
        await _tap(tester, 'Save goal');
        expect(find.text('1 rep to go'), findsOneWidget);
        await _tap(tester, 'Edit goal');
        await _tap(tester, 'Remove goal');
        final remove = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Remove goal'),
        );
        await tester.tap(remove);
        await _settle(tester);
        expect(find.text('Set goal'), findsOneWidget);

        await _tooltip(tester, 'Exercise options');
        await _tap(tester, 'Archive exercise');
        await _tap(tester, 'Archive');
        expect(find.text('Repetitions · Archived'), findsOneWidget);
        await _tap(tester, 'Restore exercise');
        expect(find.text('Repetitions · Archived'), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await _settle(tester);
        await repo.close();
        repo = open();
        await _present(tester, repo);
        expect(find.text('18 reps'), findsWidgets);
        final restored = await repo.snapshot();
        expect(
          restored.entries.where((e) => e.sets.length == 3).single.best,
          24,
        );

        await _tap(tester, 'History');
        await _tap(tester, '11');
        await _tooltip(tester, 'Options for Push-ups on 11 Nov 2026');
        await _tap(tester, 'Delete entry');
        await _tap(tester, 'Delete entry');
        expect(find.textContaining('Best 24 reps'), findsNothing);
        expect((await repo.snapshot()).entries.single.sets.single.value, 100);
        expect(tester.takeException(), isNull);
      } catch (_) {
        await capture('log-failure');
        rethrow;
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _settle(tester);
        await repo.close();
        await directory.delete(recursive: true);
      }
    },
  );

  testWidgets('validate AI paste, reject bad data and block a repeated batch', (
    tester,
  ) async {
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    final repo = TrackerRepository(
      TrackerDatabase(NativeDatabase.memory()),
      now: () => _now,
    );
    try {
      await _present(tester, repo);
      await _tooltip(tester, 'Settings');
      await _tap(tester, 'Import from AI chat');
      await _tap(tester, 'Copy AI prompt');
      expect(find.text('Prompt copied.'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField).first,
        '{"format":"wrong"}',
      );
      await _tap(tester, 'Validate and preview');
      expect(
        find.textContaining('Expected fitness-activity-import'),
        findsOneWidget,
      );
      expect((await repo.snapshot()).entries, isEmpty);
      await tester.enterText(
        find.byType(TextField).first,
        activityExample(_today),
      );
      await _tap(tester, 'Validate and preview');
      expect(
        find.widgetWithText(FilledButton, 'Confirm import'),
        findsOneWidget,
      );
      await _reveal(tester, find.text('Import preview', skipOffstage: false));
      expect(find.text('Import preview'), findsOneWidget);
      expect(find.textContaining('Create "Plank"'), findsOneWidget);
      await _tap(tester, 'Confirm import');
      expect((await repo.snapshot()).entries, hasLength(2));

      await _tap(tester, 'Import from AI chat');
      await tester.enterText(
        find.byType(TextField).first,
        activityExample(_today),
      );
      await _tap(tester, 'Validate and preview');
      await _reveal(tester, find.text('Import again', skipOffstage: false));
      expect(find.text('Import again'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Confirm import'),
      );
      expect(button.onPressed, isNull);
      await capture('05-ai-preview');
      await _tap(tester, 'Import again');
      await _tap(tester, 'Confirm import');
      final data = await repo.snapshot();
      expect(data.entries, hasLength(4));
      expect(data.receipts, hasLength(1));
      expect(tester.takeException(), isNull);
    } catch (_) {
      await capture('transfer-failure');
      rethrow;
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
      await repo.close();
    }
  });
}
