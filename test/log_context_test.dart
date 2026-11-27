import 'dart:async';

import 'package:drift/native.dart';
import 'package:fitness_tracker/app/providers.dart';
import 'package:fitness_tracker/app/theme.dart';
import 'package:fitness_tracker/core/database/database.dart'
    show TrackerDatabase;
import 'package:fitness_tracker/core/database/tracker_repository.dart';
import 'package:fitness_tracker/features/history/history_page.dart';
import 'package:fitness_tracker/shared/domain/training.dart';
import 'package:fitness_tracker/shared/widgets/ui.dart' show RowLink;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

final _now = DateTime(2026, 11, 26, 12);
final _today = CalendarDay.fromDate(_now);

Future<void> _pumpHistory(
  WidgetTester tester,
  TrackerRepository repository, {
  double width = 402,
  double height = 874,
  double scale = 1,
  Future<PreviousSet?> Function(PreviousSetFilter)? previousSetLoader,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repository),
        nowProvider.overrideWithValue(() => _now),
        if (previousSetLoader != null)
          previousSetProvider.overrideWith(
            (_, filter) => previousSetLoader(filter),
          ),
      ],
      child: MaterialApp(
        theme: trackerTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const Scaffold(body: HistoryPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _visibleText(String text) => find.text(text).hitTestable();

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.tap(_visibleText(text).first);
  await tester.pumpAndSettle();
}

Future<void> _openLogForHistory(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Add').first);
  await tester.pumpAndSettle();
  await _tapText(tester, 'Add');
}

Future<void> _clean(WidgetTester tester, TrackerRepository repository) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await repository.close();
}

void main() {
  testWidgets(
    'picker shows latest reps and copies a weighted set for editing',
    (tester) async {
      final repository = TrackerRepository(
        TrackerDatabase(NativeDatabase.memory()),
        now: () => _now,
      );
      final bench = await repository.createExercise(
        'Bench press',
        Measurement.weightAndReps,
        trackSets: true,
      );
      await repository.log([
        EntryDraft(
          exerciseId: bench.id,
          day: _today.plusDays(-2),
          sets: [(id: null, value: 60500, reps: 8)],
        ),
        EntryDraft(
          exerciseId: bench.id,
          day: _today.plusDays(-1),
          sets: [(id: null, value: 65000, reps: 6)],
        ),
      ]);
      try {
        await _pumpHistory(
          tester,
          repository,
          width: 320,
          height: 740,
          scale: 2,
        );
        await _tapText(tester, '24');
        await _openLogForHistory(tester);
        expect(find.textContaining('Latest 65 kg × 6 reps'), findsOneWidget);
        final benchRow = find.ancestor(
          of: find.text('Bench press'),
          matching: find.byType(RowLink),
        );
        await tester.ensureVisible(benchRow.first);
        await tester.pumpAndSettle();
        await tester.tap(benchRow.first);
        await tester.pumpAndSettle();
        await tester.pumpAndSettle();
        expect(find.text('Previous'), findsOneWidget);
        expect(find.textContaining('24 Nov 2026'), findsWidgets);
        expect(find.text('60.5 kg × 8 reps'), findsWidgets);
        expect(find.byTooltip('Use previous set'), findsOneWidget);
        await tester.ensureVisible(find.text('Copy'));
        await tester.pumpAndSettle();
        await _tapText(tester, 'Copy');

        final fields = find.byType(TextFormField);
        expect(
          tester.widget<TextFormField>(fields.at(0)).controller!.text,
          '60.5',
        );
        expect(
          tester.widget<TextFormField>(fields.at(1)).controller!.text,
          '8',
        );
        await tester.enterText(fields.at(0), '61.5');
        await tester.enterText(fields.at(1), '10');
        await _tapText(tester, 'Save 1 set');

        final saved = (await repository.snapshot()).entries.singleWhere(
          (entry) =>
              entry.day == _today.plusDays(-2) &&
              entry.sets.single.value == 61500,
        );
        expect((saved.sets.single.value, saved.sets.single.reps), (61500, 10));
        expect(tester.takeException(), isNull);
      } finally {
        await _clean(tester, repository);
      }
    },
  );

  testWidgets('previous set context keeps its slot and retries inline', (
    tester,
  ) async {
    final repository = TrackerRepository(
      TrackerDatabase(NativeDatabase.memory()),
      now: () => _now,
    );
    final exercise = await repository.createExercise(
      'Pull-ups',
      Measurement.repetitions,
      trackSets: true,
    );
    await repository.log([
      EntryDraft(
        exerciseId: exercise.id,
        day: _today.plusDays(-1),
        sets: [(id: null, value: 12, reps: null)],
      ),
    ]);
    final pending = Completer<PreviousSet?>();
    var attempts = 0;
    try {
      await _pumpHistory(
        tester,
        repository,
        previousSetLoader: (_) {
          attempts++;
          return attempts == 1 ? pending.future : Future.value(null);
        },
      );
      await _openLogForHistory(tester);
      await _tapText(tester, 'Pull-ups');
      await tester.pump();

      expect(find.bySemanticsLabel('Loading previous set'), findsOneWidget);
      final setHeader = find.text('Set 1');
      final initialHeaderPosition = tester.getTopLeft(setHeader);
      pending.completeError(StateError('read failed'));
      await tester.pumpAndSettle();
      expect(find.text('Couldn’t load previous set'), findsOneWidget);
      expect(tester.getTopLeft(setHeader), initialHeaderPosition);

      await _tapText(tester, 'Retry');
      expect(attempts, 2);
      expect(find.text('No earlier set'), findsOneWidget);
      expect(tester.getTopLeft(setHeader), initialHeaderPosition);
      expect(tester.takeException(), isNull);
    } finally {
      await _clean(tester, repository);
    }
  });

  testWidgets('previous duration copies minutes and seconds before editing', (
    tester,
  ) async {
    final repository = TrackerRepository(
      TrackerDatabase(NativeDatabase.memory()),
      now: () => _now,
    );
    final plank = await repository.createExercise(
      'Plank',
      Measurement.duration,
      trackSets: true,
    );
    await repository.log([
      EntryDraft(
        exerciseId: plank.id,
        day: _today.plusDays(-1),
        sets: [(id: null, value: 95, reps: null)],
      ),
    ]);
    try {
      await _pumpHistory(tester, repository);
      await _openLogForHistory(tester);
      await _tapText(tester, 'Plank');
      await tester.pumpAndSettle();
      expect(find.textContaining('1:35'), findsOneWidget);
      await _tapText(tester, 'Copy');

      final fields = find.byType(TextFormField);
      expect(tester.widget<TextFormField>(fields.at(0)).controller!.text, '1');
      expect(tester.widget<TextFormField>(fields.at(1)).controller!.text, '35');
      await tester.enterText(fields.at(0), '2');
      await tester.enterText(fields.at(1), '5');
      await _tapText(tester, 'Save 1 set');

      final saved = (await repository.snapshot()).entries.singleWhere(
        (entry) => entry.day == _today,
      );
      expect(saved.sets.single.value, 125);
      expect(tester.takeException(), isNull);
    } finally {
      await _clean(tester, repository);
    }
  });

  testWidgets('previous repetition set copies and stays editable', (
    tester,
  ) async {
    final repository = TrackerRepository(
      TrackerDatabase(NativeDatabase.memory()),
      now: () => _now,
    );
    final exercise = await repository.createExercise(
      'Push-ups',
      Measurement.repetitions,
    );
    await repository.log([
      EntryDraft(
        exerciseId: exercise.id,
        day: _today.plusDays(-1),
        sets: [(id: null, value: 12, reps: null)],
      ),
    ]);
    try {
      await _pumpHistory(tester, repository);
      await _openLogForHistory(tester);
      await _tapText(tester, 'Push-ups');
      await tester.pumpAndSettle();
      await _tapText(tester, 'Copy');
      final field = find.byType(TextFormField).first;
      expect(tester.widget<TextFormField>(field).controller!.text, '12');
      await tester.enterText(field, '14');
      await _tapText(tester, 'Save activity');

      final saved = (await repository.snapshot()).entries.singleWhere(
        (entry) => entry.day == _today,
      );
      expect(saved.sets.single.value, 14);
    } finally {
      await _clean(tester, repository);
    }
  });

  testWidgets('Repeat workout includes every entry despite History filters', (
    tester,
  ) async {
    final repository = TrackerRepository(
      TrackerDatabase(NativeDatabase.memory()),
      now: () => _now,
    );
    final pushUps = await repository.createExercise(
      'Push-ups',
      Measurement.repetitions,
    );
    final plank = await repository.createExercise(
      'Plank',
      Measurement.duration,
    );
    await repository.log([
      EntryDraft(
        exerciseId: pushUps.id,
        day: _today,
        sets: [(id: null, value: 12, reps: null)],
      ),
      EntryDraft(
        exerciseId: plank.id,
        day: _today,
        sets: [(id: null, value: 95, reps: null)],
      ),
    ]);
    try {
      await _pumpHistory(tester, repository);
      await _tapText(tester, 'All exercises');
      await _tapText(tester, 'Push-ups');
      expect(find.text('Plank'), findsNothing);

      await tester.tap(find.byTooltip('Day actions'));
      await tester.pumpAndSettle();
      await _tapText(tester, 'Repeat workout');
      expect(find.text('Push-ups'), findsWidgets);
      expect(find.text('Plank'), findsWidgets);
      final values = find.byType(TextFormField);
      expect(tester.widget<TextFormField>(values.first).controller!.text, '12');
      expect(tester.widget<TextFormField>(values.at(1)).controller!.text, '1');
      expect(tester.widget<TextFormField>(values.at(2)).controller!.text, '35');
      expect(find.text('Save activity'), findsWidgets);
      expect(tester.takeException(), isNull);
    } finally {
      await _clean(tester, repository);
    }
  });
}
