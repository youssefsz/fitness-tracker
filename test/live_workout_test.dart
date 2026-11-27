import 'package:drift/native.dart';
import 'package:fitness_tracker/app/providers.dart';
import 'package:fitness_tracker/core/database/database.dart'
    show TrackerDatabase;
import 'package:fitness_tracker/core/database/tracker_repository.dart';
import 'package:fitness_tracker/main.dart';
import 'package:fitness_tracker/shared/domain/training.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

final _now = DateTime(2026, 11, 27, 12);

class _FailingLogRepository extends TrackerRepository {
  _FailingLogRepository()
    : super(TrackerDatabase(NativeDatabase.memory()), now: () => _now);

  @override
  Future<void> log(List<EntryDraft> drafts) async {
    throw const TrackerException('Local storage was unavailable.');
  }
}

Future<void> _pumpApp(
  WidgetTester tester,
  TrackerRepository repository, {
  double width = 402,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 874);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repository),
        nowProvider.overrideWithValue(() => _now),
      ],
      child: const FitnessApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _clean(WidgetTester tester, TrackerRepository repository) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await repository.close();
}

Finder _visibleText(String text) => find.text(text).hitTestable();

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.tap(_visibleText(text).first);
  await tester.pumpAndSettle();
}

Future<void> _openPicker(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Add entry'));
  await tester.pumpAndSettle();
}

Future<void> _startLive(WidgetTester tester) async {
  await _openPicker(tester);
  await _tapText(tester, 'Start live workout');
}

Future<void> _selectExercise(WidgetTester tester, String exercise) async {
  await _tapText(tester, exercise);
}

void main() {
  testWidgets('regular logging hides timer even when its preference is on', (
    tester,
  ) async {
    final repository = TrackerRepository(
      TrackerDatabase(NativeDatabase.memory()),
      now: () => _now,
    );
    final exercise = await repository.createExercise(
      'Squats',
      Measurement.repetitions,
      trackSets: true,
    );
    await repository.saveRestTimerEnabled(true);
    try {
      await _pumpApp(tester, repository);
      await _openPicker(tester);
      await _selectExercise(tester, exercise.name);
      expect(find.text('Add entry'), findsOneWidget);
      expect(find.text('Rest timer'), findsNothing);

      await tester.enterText(find.byType(TextFormField).first, '12');
      await _tapText(tester, 'Save 1 set');
      expect((await repository.snapshot()).entries.single.latest, 12);
      expect(tester.takeException(), isNull);
    } finally {
      await _clean(tester, repository);
    }
  });

  testWidgets('live workout timer is opt-in and can be started and stopped', (
    tester,
  ) async {
    final repository = TrackerRepository(
      TrackerDatabase(NativeDatabase.memory()),
      now: () => _now,
    );
    final exercise = await repository.createExercise(
      'Squats',
      Measurement.repetitions,
      trackSets: true,
    );
    await repository.savePreferences((
      appearance: Appearance.dark,
      duration: defaultPreferences.duration,
      haptics: defaultPreferences.haptics,
      overviewExerciseOrder: defaultPreferences.overviewExerciseOrder,
    ));
    try {
      await _pumpApp(tester, repository, width: 320, textScale: 2);
      expect(tester.takeException(), isNull, reason: 'Opening Overview');
      await _startLive(tester);
      expect(tester.takeException(), isNull, reason: 'Opening Live workout');
      await _selectExercise(tester, exercise.name);
      expect(tester.takeException(), isNull, reason: 'Selecting an exercise');
      expect(find.text('Live workout'), findsOneWidget);
      expect(find.text('Rest timer'), findsNothing);
      await tester.enterText(find.byType(TextFormField).first, '10');
      await tester.tap(find.byTooltip('Cancel entry'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Opening discard dialog');
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        '10',
      );
      expect((await repository.snapshot()).entries, isEmpty);
      await tester.tap(find.byTooltip('Cancel entry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard').last);
      await tester.pumpAndSettle();

      await repository.saveRestTimerEnabled(true);
      await tester.pumpAndSettle();
      await _startLive(tester);
      await _selectExercise(tester, exercise.name);
      expect(
        tester.takeException(),
        isNull,
        reason: 'Showing the timer action',
      );
      expect(find.text('Rest 1:30'), findsOneWidget);
      await _tapText(tester, 'Start rest');
      expect(find.text('1:30'), findsOneWidget);
      await _tapText(tester, '+15 sec');
      expect(find.text('1:45'), findsOneWidget);
      await _tapText(tester, '−15 sec');
      expect(find.text('1:30'), findsOneWidget);
      await tester.tap(find.byTooltip('Stop rest timer'));
      await tester.pumpAndSettle();
      expect(find.text('1:30'), findsNothing);
      await _tapText(tester, 'Rest 1:30');
      expect(
        tester.takeException(),
        isNull,
        reason: 'Choosing a rest duration',
      );
      await _tapText(tester, '2 minutes');
      expect(tester.takeException(), isNull, reason: 'Changing rest duration');
      expect(find.text('Rest 2:00'), findsOneWidget);
      await _tapText(tester, 'Start rest');
      expect(find.text('2:00'), findsOneWidget);
      await tester.tap(find.byTooltip('Stop rest timer'));
      await tester.pumpAndSettle();
      expect(find.text('2:00'), findsNothing);
      expect(find.text('Rest 2:00'), findsOneWidget);
      await _tapText(tester, 'Start rest');
      expect(find.text('2:00'), findsOneWidget);
      await tester.tap(find.byTooltip('Stop rest timer'));
      await tester.pumpAndSettle();
      expect((await repository.snapshot()).entries, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await _clean(tester, repository);
    }
  });

  testWidgets(
    'live completion supports edit, undo, removal and saves only completed sets',
    (tester) async {
      final repository = TrackerRepository(
        TrackerDatabase(NativeDatabase.memory()),
        now: () => _now,
      );
      final exercise = await repository.createExercise(
        'Squats',
        Measurement.repetitions,
        trackSets: true,
      );
      await repository.saveRestTimerEnabled(true);
      try {
        await _pumpApp(tester, repository);
        await _startLive(tester);
        await _selectExercise(tester, exercise.name);
        await tester.enterText(find.byType(TextFormField).first, '12');
        await _tapText(tester, 'Complete set');
        await _tapText(tester, 'Undo complete set');
        await tester.enterText(find.byType(TextFormField).first, '14');
        await _tapText(tester, 'Complete set');

        await _tapText(tester, 'Add set');
        await tester.enterText(find.byType(TextFormField).first, '19');
        await tester.tap(find.byTooltip('Remove set 2'));
        await tester.pumpAndSettle();
        expect(find.text('Set 2'), findsNothing);

        await _tapText(tester, 'Add set');
        await tester.enterText(find.byType(TextFormField).first, '18');
        expect((await repository.snapshot()).entries, isEmpty);
        await _tapText(tester, 'Finish workout');
        expect(find.text('Skip incomplete sets?'), findsOneWidget);
        expect(find.textContaining('1 completed set'), findsOneWidget);
        expect(find.textContaining('skip 1 incomplete set'), findsOneWidget);
        await tester.tap(find.text('Finish workout').last);
        await tester.pumpAndSettle();

        final saved = (await repository.snapshot()).entries.single;
        expect(saved.sets, hasLength(1));
        expect(saved.sets.single.value, 14);
        expect(saved.sets.single.id, isNotEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await _clean(tester, repository);
      }
    },
  );

  testWidgets('copying the previous set cannot overwrite a completed set', (
    tester,
  ) async {
    final repository = TrackerRepository(
      TrackerDatabase(NativeDatabase.memory()),
      now: () => _now,
    );
    final exercise = await repository.createExercise(
      'Squats',
      Measurement.repetitions,
    );
    final today = CalendarDay.fromDate(_now);
    await repository.log([
      EntryDraft(
        exerciseId: exercise.id,
        day: today.plusDays(-1),
        sets: [(id: null, value: 18, reps: null)],
      ),
    ]);
    try {
      await _pumpApp(tester, repository);
      await _startLive(tester);
      await _selectExercise(tester, exercise.name);
      expect(find.text('Copy'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, '12');
      await _tapText(tester, 'Complete set');
      expect(find.text('Copy'), findsNothing);
      await _tapText(tester, 'Finish workout');
      final saved = (await repository.snapshot()).entries.singleWhere(
        (entry) => entry.day == today,
      );
      expect(saved.sets.single.value, 12);
      expect(tester.takeException(), isNull);
    } finally {
      await _clean(tester, repository);
    }
  });

  testWidgets('live write failure leaves completed draft editable', (
    tester,
  ) async {
    final repository = _FailingLogRepository();
    final exercise = await repository.createExercise(
      'Squats',
      Measurement.repetitions,
      trackSets: true,
    );
    try {
      await _pumpApp(tester, repository);
      await _startLive(tester);
      await _selectExercise(tester, exercise.name);
      await tester.enterText(find.byType(TextFormField).first, '21');
      await _tapText(tester, 'Complete set');
      await _tapText(tester, 'Finish workout');
      expect(find.text('Local storage was unavailable.'), findsOneWidget);
      final input = tester.widget<TextFormField>(find.byType(TextFormField));
      expect(input.controller!.text, '21');
      expect((await repository.snapshot()).entries, isEmpty);
      expect(find.text('Live workout'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await _clean(tester, repository);
    }
  });
}
