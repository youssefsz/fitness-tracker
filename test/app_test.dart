import 'dart:async';

import 'package:drift/native.dart';
import 'package:fitness_tracker/app/providers.dart';
import 'package:fitness_tracker/core/database/database.dart'
    show TrackerDatabase;
import 'package:fitness_tracker/core/database/tracker_repository.dart';
import 'package:fitness_tracker/core/platform/device_services.dart';
import 'package:fitness_tracker/main.dart';
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
  testWidgets(
    'empty, validation, retained draft, double save guard and haptic preference',
    (tester) async {
      final repo = _DeferredRepository(
        TrackerDatabase(NativeDatabase.memory()),
      );
      final feedback = _Feedback();
      await repo.createExercise('Push-ups', Measurement.repetitions);
      try {
        await _pumpApp(tester, repo, feedback: feedback);
        expect(find.text('Start with one result.'), findsOneWidget);
        await tapText(tester, 'Record your first result');
        await tapText(tester, 'Push-ups');
        await tapText(tester, 'Save 1 set');
        expect(find.textContaining('Enter a whole number'), findsOneWidget);
        await tester.enterText(find.byType(TextFormField).first, '22');
        await tapText(tester, 'Add set');
        await tester.enterText(find.byType(TextFormField).at(1), '18');
        await tapText(tester, 'Cancel');
        expect(find.text('Discard changes?'), findsOneWidget);
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Cancel'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('22'), findsOneWidget);
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
        await tester.tap(find.byTooltip('Settings'));
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
    'bootstrap failure is recoverable and never presents an empty dashboard first',
    (tester) async {
      final repo = _RetryRepository(TrackerDatabase(NativeDatabase.memory()));
      try {
        await _pumpApp(tester, repo);
        expect(find.text('V couldn’t open your records'), findsOneWidget);
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
            sets: [(id: null, value: 78)],
          ),
          EntryDraft(
            exerciseId: x.id,
            day: today,
            sets: [(id: null, value: 100), (id: null, value: 90)],
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
