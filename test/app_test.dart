import 'dart:async';

import 'package:drift/native.dart';
import 'package:fitness_tracker/app/providers.dart';
import 'package:fitness_tracker/core/database/database.dart'
    show TrackerDatabase;
import 'package:fitness_tracker/core/database/tracker_repository.dart';
import 'package:fitness_tracker/core/platform/device_services.dart';
import 'package:fitness_tracker/main.dart';
import 'package:fitness_tracker/features/profile/profile_page.dart';
import 'package:fitness_tracker/shared/domain/body_metrics.dart';
import 'package:fitness_tracker/shared/domain/training.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final fixedNow = DateTime(2026, 11, 12, 12);

class _Feedback implements FeedbackService {
  int selects = 0, saves = 0;
  @override
  Future<void> saved() async {
    saves++;
  }

  @override
  Future<void> selection() async {
    selects++;
  }
}

class _LocalCopies extends DeviceTransferFiles {
  int clears = 0;

  @override
  Future<void> clearLocalCopies() async => clears++;
}

class _DeferredRepository extends TrackerRepository {
  _DeferredRepository(super.database) : super(now: () => fixedNow);
  final entered = Completer<void>();
  final release = Completer<void>();
  int calls = 0;

  @override
  Future<void> log(List<EntryDraft> drafts) async {
    calls++;
    if (!entered.isCompleted) entered.complete();
    await release.future;
    await super.log(drafts);
  }
}

class _RetryRepository extends TrackerRepository {
  _RetryRepository(super.db) : super(now: () => fixedNow);
  int attempts = 0;

  @override
  Future<void> open() async {
    attempts++;
    if (attempts == 1) {
      throw const TrackerException('Local storage was unavailable.');
    }
    await super.open();
  }
}

Future<void> _pumpApp(
  WidgetTester tester,
  TrackerRepository repo, {
  _Feedback? feedback,
  TransferFiles? files,
  double width = 402,
  double height = 874,
  double scale = 1.0,
  bool reducedMotion = false,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(disableAnimations: reducedMotion);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        nowProvider.overrideWithValue(() => fixedNow),
        if (feedback != null) feedbackProvider.overrideWithValue(feedback),
        if (files != null) filesProvider.overrideWithValue(files),
      ],
      child: const FitnessApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> clean(WidgetTester tester, TrackerRepository repo) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await repo.close();
}

Finder visibleText(String text) => find.text(text).hitTestable();

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(visibleText(text).first);
  await tester.pumpAndSettle();
}

void main() {
  for (final (appearance, background, surface) in [
    (Appearance.light, const Color(0xfffafafa), Colors.white),
    (Appearance.dark, const Color(0xff121212), const Color(0xff1d1d1d)),
  ]) {
    testWidgets('activity date uses neutral ${appearance.name} colors', (
      tester,
    ) async {
      final repo = TrackerRepository(TrackerDatabase(NativeDatabase.memory()));
      await repo.createExercise(
        'Push-ups',
        Measurement.repetitions,
        trackSets: true,
      );
      await repo.savePreferences((
        appearance: appearance,
        duration: DurationStyle.clock,
        haptics: false,
      ));
      try {
        await _pumpApp(tester, repo);
        expect(
          Theme.of(tester.element(visibleText('Start with one result.')))
              .scaffoldBackgroundColor,
          background,
        );
        await tester.tap(find.byTooltip('Add entry'));
        await tester.pumpAndSettle();
        await tapText(tester, 'Push-ups');
        await tapText(tester, 'Change');
        final dialog = find.descendant(
          of: find.byType(DatePickerDialog),
          matching: find.byType(Dialog),
        );
        expect(tester.widget<Dialog>(dialog).backgroundColor, surface);
      } finally {
        await clean(tester, repo);
      }
    });
  }

  testWidgets(
    'log sheet dismisses by backdrop and drag with draft protection',
    (tester) async {
      final repo = TrackerRepository(TrackerDatabase(NativeDatabase.memory()));
      await repo.createExercise(
        'Push-ups',
        Measurement.repetitions,
        trackSets: true,
      );
      try {
        await _pumpApp(tester, repo);
        final add = find.byTooltip('Add entry');
        const backdrop = Offset(20, 34);
        final sheet = find.byType(BottomSheet);
        await tester.tap(add);
        await tester.pumpAndSettle();
        await tester.tapAt(backdrop);
        await tester.pumpAndSettle();
        expect(sheet, findsNothing);

        await tester.tap(add);
        await tester.pumpAndSettle();
        final top = tester.getTopLeft(sheet).dy;
        final drag = await tester.startGesture(Offset(201, top + 16));
        await drag.moveBy(const Offset(0, 25));
        await drag.moveBy(const Offset(0, 145));
        await tester.pump();
        expect(tester.getTopLeft(sheet).dy, greaterThan(top));
        await drag.moveBy(const Offset(0, 320));
        await drag.up();
        await tester.pumpAndSettle();
        expect(sheet, findsNothing);

        await tester.tap(add);
        await tester.pumpAndSettle();
        await tapText(tester, 'Push-ups');
        await tester.enterText(find.byType(TextFormField), '19');
        await tester.tapAt(backdrop);
        await tester.pumpAndSettle();
        expect(find.text('Discard changes?'), findsOneWidget);
        await tapText(tester, 'Cancel');
        expect(visibleText('19'), findsOneWidget);

        await tester.dragFrom(
          Offset(201, tester.getTopLeft(sheet).dy + 16),
          const Offset(0, 520),
        );
        await tester.pumpAndSettle();
        expect(find.text('Discard changes?'), findsOneWidget);
        await tapText(tester, 'Discard');
        expect(sheet, findsNothing);
        expect((await repo.snapshot()).entries, isEmpty);
      } finally {
        await clean(tester, repo);
      }
    },
  );

  testWidgets(
    'creating an exercise stays in the log sheet and keeps the draft',
    (tester) async {
      final repo = TrackerRepository(TrackerDatabase(NativeDatabase.memory()));
      await repo.createExercise(
        'Push-ups',
        Measurement.repetitions,
        trackSets: true,
      );
      try {
        await _pumpApp(tester, repo);
        await tester.tap(find.byTooltip('Add entry'));
        await tester.pumpAndSettle();
        await tapText(tester, 'Push-ups');
        await tester.enterText(find.byType(TextFormField), '19');
        await tapText(tester, 'Add another exercise');
        final sheet = tester.element(find.byType(BottomSheet));
        await tapText(tester, 'Create exercise');
        expect(visibleText('New exercise'), findsOneWidget);
        expect(tester.element(find.byType(BottomSheet)), same(sheet));
        await tester.enterText(find.byType(TextField), 'Unfinished exercise');
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        expect(find.text('Discard changes?'), findsOneWidget);
        await tapText(tester, 'Discard');
        expect(visibleText('Choose exercise'), findsOneWidget);
        await tapText(tester, 'Create exercise');
        await tester.enterText(find.byType(TextField), 'Squats');
        await tapText(tester, 'Create exercise');
        expect(tester.element(find.byType(BottomSheet)), same(sheet));
        expect(visibleText('Save activity'), findsOneWidget);
        expect(visibleText('19'), findsOneWidget);
        expect(visibleText('Squats'), findsOneWidget);
      } finally {
        await clean(tester, repo);
      }
    },
  );

  testWidgets(
    'an exercise created before the first result can be deleted from Overview',
    (tester) async {
      final repo = TrackerRepository(TrackerDatabase(NativeDatabase.memory()));
      try {
        await _pumpApp(tester, repo);
        await tapText(tester, 'Record your first result');
        await tapText(tester, 'Create exercise');
        await tester.enterText(find.byType(TextField), 'Squats');
        await tapText(tester, 'Create exercise');
        expect(visibleText('Save activity'), findsOneWidget);
        await tester.tap(find.byTooltip('Cancel entry'));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);

        await tapText(tester, 'Manage exercises');
        final menu = find.byTooltip('Manage Squats');
        await tester.tap(menu);
        await tester.pumpAndSettle();
        await tapText(tester, 'Delete exercise');
        expect(find.text('Delete Squats?'), findsOneWidget);
        await tapText(tester, 'Cancel');
        expect(visibleText('Squats'), findsOneWidget);

        await tester.tap(menu);
        await tester.pumpAndSettle();
        await tapText(tester, 'Delete exercise');
        await tapText(tester, 'Delete exercise');
        expect(find.text('Squats'), findsNothing);
        expect(find.text('Build your exercise list'), findsOneWidget);
        final snapshot = await repo.snapshot();
        expect(snapshot.exercises, isEmpty);
        expect(snapshot.entries, isEmpty);
      } finally {
        await clean(tester, repo);
      }
    },
  );

  testWidgets(
    'archiving hides records across tabs, restoring returns them, and deletion removes them',
    (tester) async {
      final repo = TrackerRepository(
        TrackerDatabase(NativeDatabase.memory()),
        now: () => fixedNow,
      );
      try {
        final demo = await repo.createExercise(
          'Demo squats',
          Measurement.repetitions,
        );
        final keep = await repo.createExercise(
          'Push-ups',
          Measurement.repetitions,
        );
        await repo.log([
          for (final exercise in [demo, keep])
            EntryDraft(
              exerciseId: exercise.id,
              day: CalendarDay.fromDate(fixedNow),
              sets: [(id: null, value: 15, reps: null)],
            ),
        ]);
        await _pumpApp(tester, repo);
        await tapText(tester, 'History');
        await tapText(tester, 'All exercises');
        await tapText(tester, 'Demo squats');
        await tapText(tester, 'Overview');
        await tapText(tester, 'Manage');
        await tester.tap(find.byTooltip('Manage Demo squats'));
        await tester.pumpAndSettle();
        await tapText(tester, 'Archive');
        await tapText(tester, 'Archive');
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        expect(find.text('Demo squats'), findsNothing);
        await tapText(tester, 'Progress');
        expect(visibleText('Push-ups'), findsOneWidget);
        await tapText(tester, 'History');
        expect(visibleText('All exercises'), findsOneWidget);
        expect(find.text('Demo squats'), findsNothing);
        expect(find.text('Push-ups'), findsWidgets);

        await tapText(tester, 'Overview');
        await tapText(tester, 'Manage');
        await tapText(tester, 'Restore');
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        expect(visibleText('Demo squats'), findsWidgets);
        await tapText(tester, 'Progress');
        expect(visibleText('Demo squats'), findsOneWidget);
        await tapText(tester, 'History');
        expect(find.text('Demo squats'), findsWidgets);

        await tapText(tester, 'Overview');
        await tapText(tester, 'Demo squats');
        await tester.tap(find.byTooltip('Exercise options'));
        await tester.pumpAndSettle();
        await tapText(tester, 'Delete exercise');
        await tapText(tester, 'Delete exercise');
        expect(find.byTooltip('Exercise options'), findsNothing);
        expect(find.text('Demo squats'), findsNothing);
        expect((await repo.snapshot()).entries.single.exerciseId, keep.id);
      } finally {
        await clean(tester, repo);
      }
    },
  );

  testWidgets(
    'Profile exposes separate confirmed resets for workouts and all data',
    (tester) async {
      final repo = TrackerRepository(
        TrackerDatabase(NativeDatabase.memory()),
        now: () => fixedNow,
      );
      final files = _LocalCopies();
      try {
        await repo.createExercise('Demo squats', Measurement.repetitions);
        await repo.saveWeighIn((
          day: CalendarDay.fromDate(fixedNow),
          grams: 80125,
        ));
        await _pumpApp(tester, repo, files: files);
        await tester.tap(find.byTooltip('Profile'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Your data'));
        await tapText(tester, 'Your data');
        await tester.ensureVisible(find.text('Delete all exercises'));
        await tapText(tester, 'Delete all exercises');
        await tapText(tester, 'Cancel');
        expect((await repo.snapshot()).exercises, hasLength(1));
        await tapText(tester, 'Delete all exercises');
        await tapText(tester, 'Delete all exercises');
        expect((await repo.snapshot()).exercises, isEmpty);
        expect((await repo.snapshot()).body!.weighIns, hasLength(1));
        expect(files.clears, 0);
        await tester.ensureVisible(find.text('Reset all app data'));
        await tapText(tester, 'Reset all app data');
        await tapText(tester, 'Reset all app data');
        expect((await repo.snapshot()).body!.weighIns, isEmpty);
        expect(files.clears, 1);
      } finally {
        await clean(tester, repo);
      }
    },
  );

  testWidgets(
    'empty, validation, retained draft, double save guard and haptic preference',
    (tester) async {
      final repo = _DeferredRepository(
        TrackerDatabase(NativeDatabase.memory()),
      );
      final feedback = _Feedback();
      await repo.createExercise(
        'Push-ups',
        Measurement.repetitions,
        trackSets: true,
      );
      try {
        await _pumpApp(tester, repo, feedback: feedback);
        expect(find.text('Start with one result.'), findsOneWidget);
        await tapText(tester, 'Record your first result');
        expect(find.byType(BottomSheet), findsOneWidget);
        await tapText(tester, 'Push-ups');
        await tapText(tester, 'Save 1 set');
        expect(find.textContaining('Enter a whole number'), findsOneWidget);
        await tester.enterText(find.byType(TextFormField).first, '22');
        await tapText(tester, 'Add set');
        await tester.enterText(find.byType(TextFormField).first, '18');
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        expect(visibleText('Choose exercise'), findsOneWidget);
        await tapText(tester, 'Continue to sets');
        expect(visibleText('22 reps'), findsOneWidget);
        expect(visibleText('18'), findsOneWidget);
        await tester.tap(find.byTooltip('Cancel entry'));
        await tester.pumpAndSettle();
        expect(find.text('Discard changes?'), findsOneWidget);
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Cancel'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('22 reps'), findsOneWidget);
        expect(find.text('18'), findsOneWidget);

        final save = visibleText('Save 2 sets');
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.resetViewInsets);
        await tester.pump();
        ScaffoldMessenger.of(tester.element(save)).showSnackBar(
          const SnackBar(content: Text('Saved a previous entry.')),
        );
        await tester.pump(const Duration(milliseconds: 280));
        expect(tester.getBottomLeft(save).dy, lessThan(874 - 280));
        await tester.tap(save);
        await tester.tap(save);
        tester.view.resetViewInsets();
        await tester.pump();
        expect(repo.calls, 1);
        expect(feedback.saves, 0);
        repo.release.complete();
        await tester.pumpAndSettle();
        expect(feedback.saves, 1);
        expect(feedback.selects, 1);
        expect(
          (await repo.snapshot()).entries.single.sets.map((s) => s.value),
          [22, 18],
        );
        expect(find.text('18 reps'), findsWidgets);
        await tester.tap(find.byTooltip('Profile'));
        await tester.pumpAndSettle();
        await tapText(tester, 'Haptics');
        expect((await repo.snapshot()).preferences.haptics, isFalse);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tapText(tester, 'History');
        expect(feedback.selects, 1);
        expect(tester.takeException(), isNull);
      } finally {
        if (!repo.release.isCompleted) repo.release.complete();
        await clean(tester, repo);
      }
    },
  );

  testWidgets(
    'entry sheet follows keyboard dismissal without a final height jump',
    (tester) async {
      final repo = TrackerRepository(TrackerDatabase(NativeDatabase.memory()));
      await repo.createExercise('Pull-ups', Measurement.repetitions);
      try {
        tester.view.viewPadding = const FakeViewPadding(bottom: 34);
        addTearDown(tester.view.resetViewPadding);
        addTearDown(tester.view.resetViewInsets);
        await _pumpApp(tester, repo);
        await tapText(tester, 'Record your first result');
        await tapText(tester, 'Pull-ups');
        final input = find.byType(TextFormField).first;
        await tester.enterText(input, '12');
        final heading = visibleText('Add entry');
        final save = visibleText('Save activity');
        final restingTop = tester.getTopLeft(heading).dy;
        final restingSave = tester.getBottomLeft(save).dy;

        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        final keyboardSave = tester.getBottomLeft(save).dy;
        expect(keyboardSave, lessThan(874 - 300));

        if (Theme.of(tester.element(save)).platform == TargetPlatform.iOS) {
          tester.view.viewInsets = const FakeViewPadding(bottom: 150);
          await tester.pump();
          expect(
            tester.getBottomLeft(save).dy,
            inExclusiveRange(keyboardSave, restingSave),
          );
          tester.view.viewInsets = const FakeViewPadding(bottom: 1);
          await tester.pump();
          expect(tester.getTopLeft(heading).dy, closeTo(restingTop, 1));
        } else {
          tester.view.resetViewInsets();
          await tester.pump();
          expect(tester.getBottomLeft(save).dy, keyboardSave);
          await tester.pump(const Duration(milliseconds: 80));
          expect(
            tester.getBottomLeft(save).dy,
            inExclusiveRange(keyboardSave, restingSave),
          );
        }

        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(heading).dy, restingTop);
        expect(tester.getBottomLeft(save).dy, restingSave);
        expect(
          find.descendant(of: input, matching: find.text('12')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await clean(tester, repo);
      }
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

  testWidgets('correcting an exercise keeps compatible draft sets', (
    tester,
  ) async {
    final repo = TrackerRepository(TrackerDatabase(NativeDatabase.memory()));
    await repo.createExercise(
      'Push-ups',
      Measurement.repetitions,
      trackSets: true,
    );
    await repo.createExercise(
      'Pull-ups',
      Measurement.repetitions,
      trackSets: true,
    );
    await repo.createExercise('Plank', Measurement.duration, trackSets: true);
    try {
      await _pumpApp(tester, repo);
      await tapText(tester, 'Record your first result');
      await tapText(tester, 'Push-ups');
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).first)
            .focusNode
            .hasFocus,
        isTrue,
      );
      await tester.enterText(find.byType(TextFormField).first, '12');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tapText(tester, 'Pull-ups');
      expect(visibleText('Pull-ups'), findsOneWidget);
      expect(visibleText('12'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Plank');
      expect(find.text('Switch to Plank?'), findsOneWidget);
      await tapText(tester, 'Cancel');
      await tapText(tester, 'Continue to sets');
      expect(visibleText('Pull-ups'), findsOneWidget);
      expect(visibleText('12'), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).first)
            .focusNode
            .hasFocus,
        isTrue,
      );

      await tapText(tester, 'Add another exercise');
      await tapText(tester, 'Plank');
      expect(visibleText('12'), findsOneWidget);
      expect(visibleText('Save 2 sets'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(visibleText('Plank'), findsOneWidget);
      expect(visibleText('Pull-ups'), findsNothing);
      await tapText(tester, 'Continue to sets');
      expect(visibleText('12'), findsOneWidget);
      expect((await repo.snapshot()).entries, isEmpty);
    } finally {
      await clean(tester, repo);
    }
  });

  testWidgets(
    'a single-result exercise logs zero and rejects blank and negative values',
    (tester) async {
      final repo = TrackerRepository(
        TrackerDatabase(NativeDatabase.memory()),
        now: () => fixedNow,
      );
      try {
        await _pumpApp(tester, repo);
        await tapText(tester, 'Record your first result');
        await tapText(tester, 'Create exercise');
        await tester.enterText(find.byType(TextField).first, 'Pull-ups');
        expect(
          tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          isFalse,
        );
        await tapText(tester, 'Create exercise');
        expect(find.text('Add set'), findsNothing);
        final amount = find.byType(TextFormField);
        await tapText(tester, 'Save activity');
        expect(
          find.textContaining('Enter a whole number from 0'),
          findsOneWidget,
        );
        await tester.enterText(amount, '-1');
        await tapText(tester, 'Save activity');
        expect((await repo.snapshot()).entries, isEmpty);
        await tester.enterText(amount, '0');
        await tapText(tester, 'Save activity');
        expect((await repo.snapshot()).entries.single.latest, 0);
        expect(find.text('0 reps'), findsWidgets);
        await tapText(tester, 'Progress');
        expect(find.text('0 reps'), findsWidgets);
        expect(tester.takeException(), isNull);
      } finally {
        await clean(tester, repo);
      }
    },
  );

  testWidgets('weighted sets show both values and survive turning sets off', (
    tester,
  ) async {
    final repo = TrackerRepository(
      TrackerDatabase(NativeDatabase.memory()),
      now: () => fixedNow,
    );
    try {
      await _pumpApp(tester, repo);
      await tapText(tester, 'Record your first result');
      await tapText(tester, 'Create exercise');
      await tester.enterText(find.byType(TextField).first, 'Bench press');
      await tapText(tester, 'Weight + reps');
      await tester.ensureVisible(find.text('Track sets'));
      await tapText(tester, 'Track sets');
      await tapText(tester, 'Create exercise');

      Future<void> enterSet(String load, String reps) async {
        await tester.enterText(find.byType(TextFormField).first, load);
        await tester.enterText(find.byType(TextFormField).at(1), reps);
        await tester.pumpAndSettle();
      }

      await enterSet('60.5', '8');
      await tapText(tester, 'Add set');
      expect(visibleText('60.5 kg × 8 reps'), findsOneWidget);
      await enterSet('65', '0');
      await tapText(tester, 'Save 2 sets');
      await tapText(tester, 'Manage');
      await tapText(tester, 'Edit');
      await tester.ensureVisible(find.text('Track sets'));
      await tapText(tester, 'Track sets');
      await tapText(tester, 'Save exercise');

      final snapshot = await repo.snapshot();
      expect(snapshot.exercises.single.trackSets, isFalse);
      expect(snapshot.entries.single.sets.map((s) => (s.value, s.reps)), [
        (60500, 8),
        (65000, 0),
      ]);
      expect(snapshot.entries.single.best, 60500);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add entry'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Bench press');
      expect(visibleText('Save activity'), findsOneWidget);
      expect(find.text('Add set'), findsNothing);
    } finally {
      await clean(tester, repo);
    }
  });

  testWidgets(
    'iOS edge swipe returns from Profile and only the tab pill slides',
    (tester) async {
      final repo = TrackerRepository(TrackerDatabase(NativeDatabase.memory()));
      try {
        await _pumpApp(tester, repo);
        await tester.tap(find.byTooltip('Profile'));
        await tester.pumpAndSettle();
        expect(visibleText('Profile'), findsOneWidget);
        await tester.dragFrom(const Offset(1, 280), const Offset(330, 0));
        await tester.pumpAndSettle();
        expect(visibleText('Start with one result.'), findsOneWidget);
        final pill = find.byKey(const ValueKey('primary-tab-indicator'));
        final start = tester.getCenter(pill).dx;
        final destination = tester.getCenter(visibleText('Progress')).dx;
        await tester.tap(visibleText('Progress'));
        await tester.pump();
        expect(visibleText('See how your sets change'), findsOneWidget);
        expect(tester.getCenter(pill).dx, start);
        await tester.pump(const Duration(milliseconds: 80));
        expect(tester.getCenter(pill).dx, inExclusiveRange(start, destination));
        await tester.pumpAndSettle();
        expect(tester.getCenter(pill).dx, closeTo(destination, 0.01));
      } finally {
        await clean(tester, repo);
      }
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets('reduced motion moves the tab pill immediately', (tester) async {
    final repo = TrackerRepository(TrackerDatabase(NativeDatabase.memory()));
    try {
      await _pumpApp(tester, repo, reducedMotion: true);
      final history = visibleText('History');
      final destination = tester.getCenter(history).dx;
      await tester.tap(history);
      await tester.pump();
      final pill = find.byKey(const ValueKey('primary-tab-indicator'));
      expect(tester.getCenter(pill).dx, closeTo(destination, 0.01));
    } finally {
      await clean(tester, repo);
    }
  });

  testWidgets(
    'Progress restores the chosen exercise when the app opens again',
    (tester) async {
      final repo = TrackerRepository(
        TrackerDatabase(NativeDatabase.memory()),
        now: () => fixedNow,
      );
      try {
        final a = await repo.createExercise('Plank', Measurement.duration);
        final b = await repo.createExercise(
          'Push-ups',
          Measurement.repetitions,
        );
        await repo.log([
          for (final exercise in [a, b])
            EntryDraft(
              exerciseId: exercise.id,
              day: CalendarDay.fromDate(fixedNow),
              sets: [(id: null, value: 12, reps: null)],
            ),
        ]);
        await _pumpApp(tester, repo);
        await tapText(tester, 'Progress');
        await tapText(tester, 'Plank');
        await tapText(tester, 'Push-ups');
        expect(visibleText('Push-ups'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await _pumpApp(tester, repo);
        await tapText(tester, 'Progress');
        expect(visibleText('Push-ups'), findsOneWidget);
      } finally {
        await clean(tester, repo);
      }
    },
  );

  testWidgets(
    'Profile and weight entry fit a compact Android viewport with large text',
    (tester) async {
      final repo = TrackerRepository(
        TrackerDatabase(NativeDatabase.memory()),
        now: () => fixedNow,
      );
      try {
        await repo.savePreferences((
          appearance: Appearance.dark,
          duration: DurationStyle.seconds,
          haptics: false,
        ));
        await _pumpApp(tester, repo, width: 320, height: 640, scale: 2);
        await tester.tap(find.byTooltip('Profile'));
        await tester.pumpAndSettle();
        final logWeight = find.text('Log weight');
        await tester.scrollUntilVisible(logWeight, 100);
        await Scrollable.ensureVisible(
          tester.element(logWeight),
          alignment: .5,
        );
        await tester.pumpAndSettle();
        await tapText(tester, 'Log weight');
        await tester.enterText(find.byType(TextFormField), '80.25');
        await tapText(tester, 'Save weight');
        expect((await repo.snapshot()).body!.weighIns.single.grams, 80250);
        final appearance = find.text('Appearance');
        await tester.scrollUntilVisible(appearance, 100);
        await tester.ensureVisible(appearance);
        await tapText(tester, 'Appearance');
        for (final label in ['System', 'Light', 'Dark']) {
          expect(visibleText(label), findsOneWidget);
        }
        await tapText(tester, 'Light');
        expect(
          (await repo.snapshot()).preferences.appearance,
          Appearance.light,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await clean(tester, repo);
      }
    },
    variant: TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets('pounds round-trip and unit changes keep stored weight', (
    tester,
  ) async {
    final repo = TrackerRepository(
      TrackerDatabase(NativeDatabase.memory()),
      now: () => fixedNow,
    );
    try {
      final older = CalendarDay.fromDate(fixedNow).plusDays(-1);
      await repo.saveWeighIn((day: older, grams: 80125));
      await _pumpApp(tester, repo);
      await tester.tap(find.byTooltip('Profile'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Log weight');
      await tapText(tester, 'lb');
      final field = find.byType(TextFormField);
      await tester.enterText(field, '55');
      await tester.pumpAndSettle();
      await tapText(tester, 'Save weight');
      expect(visibleText('55 lb'), findsOneWidget);

      await tapText(tester, 'Body weight');
      expect(find.text('176.65 lb'), findsOneWidget);
      await tapText(tester, '11 Nov 2026');
      expect(tester.widget<TextFormField>(field).controller!.text, '176.65');
      await tapText(tester, 'kg');
      expect(tester.widget<TextFormField>(field).controller!.text, '80.125');
      await tapText(tester, 'Save weight');

      final body = (await repo.snapshot()).body!;
      expect(body.profile.weightUnit, WeightUnit.kg);
      expect(body.weighIns.first.grams, 80125);
      expect(body.weighIns.last.grams, 24948);
    } finally {
      await clean(tester, repo);
    }
  });

  testWidgets(
    'height units default to metric and round-trip an edited height',
    (tester) async {
      final repo = TrackerRepository(TrackerDatabase(NativeDatabase.memory()));
      try {
        await _pumpApp(tester, repo);
        await tester.tap(find.byTooltip('Profile'));
        await tester.pumpAndSettle();
        await tapText(tester, 'Edit profile');
        expect(visibleText('cm'), findsOneWidget);
        expect(visibleText('kg'), findsOneWidget);
        await tester.enterText(
          find.widgetWithText(TextField, 'Height'),
          '178.5',
        );
        await tapText(tester, 'Height unit');
        await tapText(tester, 'Feet and inches');
        final feet = find.widgetWithText(TextField, 'Feet');
        final inches = find.widgetWithText(TextField, 'Inches');
        expect(tester.widget<TextField>(feet).controller!.text, '5');
        expect(tester.widget<TextField>(inches).controller!.text, '10.28');
        await tapText(tester, 'Save profile');
        expect(visibleText('5 ft 10.28 in'), findsOneWidget);
        expect((await repo.snapshot()).body!.profile.heightMillimeters, 1785);

        await tapText(tester, 'Edit profile');
        await tester.enterText(inches, '12');
        await tester.pumpAndSettle();
        await tapText(tester, 'Save profile');
        expect(
          visibleText(
            'Enter whole feet and 0 to 11.99 inches, up to 9 ft 10.11 in total.',
          ),
          findsOneWidget,
        );
        await tester.enterText(inches, '11');
        await tapText(tester, 'Height unit');
        await tapText(tester, 'Centimeters');
        await tapText(tester, 'Save profile');
        expect(visibleText('180.3 cm'), findsOneWidget);
        final profile = (await repo.snapshot()).body!.profile;
        expect(profile.heightUnit, HeightUnit.cm);
        expect(profile.weightUnit, WeightUnit.kg);
      } finally {
        await clean(tester, repo);
      }
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets('Edit profile back arrow prompts before discarding a draft', (
    tester,
  ) async {
    final repo = TrackerRepository(TrackerDatabase(NativeDatabase.memory()));
    try {
      await _pumpApp(tester, repo);
      await tester.tap(find.byTooltip('Profile'));
      await tester.pumpAndSettle();
      final back = find.byTooltip('Back').hitTestable();
      await tapText(tester, 'Edit profile');
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.text('Save profile'), findsNothing);

      await tapText(tester, 'Edit profile');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Display name'),
        'Unsaved name',
      );
      await tester.pumpAndSettle();
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tapText(tester, 'Cancel');
      expect(visibleText('Unsaved name'), findsOneWidget);
      await tester.tap(back);
      await tester.pumpAndSettle();
      await tapText(tester, 'Discard');
      expect(find.text('Save profile'), findsNothing);
      expect((await repo.snapshot()).body!.profile.displayName, isNull);
    } finally {
      await clean(tester, repo);
    }
  });

  testWidgets('profile avatar options fit large text and save the selection', (
    tester,
  ) async {
    final repo = TrackerRepository(TrackerDatabase(NativeDatabase.memory()));
    try {
      await _pumpApp(tester, repo, width: 320, height: 640, scale: 2);
      await tester.tap(find.byTooltip('Profile'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Edit profile');
      AvatarPreset shownPreset() =>
          tester.widget<ProfileAvatar>(find.byType(ProfileAvatar)).preset;
      expect(shownPreset(), AvatarPreset.anonymous);
      await tapText(tester, 'Change avatar');
      expect(visibleText('Default'), findsOneWidget);
      await tapText(tester, 'Mobility');
      expect(shownPreset(), AvatarPreset.mobility);
      await tapText(tester, 'Change avatar');
      await tapText(tester, 'Default');
      expect(shownPreset(), AvatarPreset.anonymous);
      expect(tester.takeException(), isNull);
    } finally {
      await clean(tester, repo);
    }
  });

  testWidgets(
    'bootstrap failure is recoverable and never presents an empty dashboard first',
    (tester) async {
      final repo = _RetryRepository(TrackerDatabase(NativeDatabase.memory()));
      try {
        await _pumpApp(tester, repo);
        expect(find.text('Couldn’t open your records'), findsOneWidget);
        expect(find.text('Start with one result.'), findsNothing);
        await tapText(tester, 'Try again');
        expect(find.text('Start with one result.'), findsOneWidget);
        expect(repo.attempts, 2);
      } finally {
        await clean(tester, repo);
      }
    },
  );

  for (final (width, height, scale, dark) in [
    (320.0, 670.0, 2.0, true),
    (430.0, 900.0, 1.3, false),
    (1024.0, 768.0, 2.0, true),
  ]) {
    testWidgets(
      'responsive tabs and chart at ${width.toInt()} points and ${scale}x text',
      (tester) async {
        final repo = TrackerRepository(
          TrackerDatabase(NativeDatabase.memory()),
          now: () => fixedNow,
        );
        final name =
            'A long exercise name that wraps cleanly even on compact screens';
        final x = await repo.createExercise(name, Measurement.duration);
        final today = CalendarDay.fromDate(fixedNow);
        await repo.log([
          EntryDraft(
            exerciseId: x.id,
            day: today.plusDays(-7),
            sets: [(id: null, value: 78, reps: null)],
          ),
          EntryDraft(
            exerciseId: x.id,
            day: today,
            sets: [
              (id: null, value: 100, reps: null),
              (id: null, value: 90, reps: null),
            ],
          ),
        ]);
        await repo.savePreferences((
          appearance: dark ? Appearance.dark : Appearance.light,
          duration: DurationStyle.clock,
          haptics: false,
        ));
        try {
          await _pumpApp(
            tester,
            repo,
            width: width,
            height: height,
            scale: scale,
            reducedMotion: true,
          );
          expect(find.text(name), findsWidgets);
          expect(
            Theme.of(tester.element(find.text('Your exercises'))).brightness,
            dark ? Brightness.dark : Brightness.light,
          );
          await tapText(tester, 'Progress');
          await tapText(tester, 'All time');
          expect(find.text('Date range'), findsOneWidget);
          await tapText(tester, 'Last 7 days');
          await tapText(tester, 'Apply range');
          expect(find.text('Last 7 days'), findsOneWidget);
          await tapText(tester, 'History');
          expect(find.byTooltip('Previous month'), findsOneWidget);
          await tester.tap(find.byTooltip('Previous month'));
          await tester.pumpAndSettle();
          expect(find.text('October 2026'), findsOneWidget);
          await tapText(tester, 'Progress');
          expect(find.text('Last 7 days'), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          await clean(tester, repo);
        }
      },
    );
  }
}
