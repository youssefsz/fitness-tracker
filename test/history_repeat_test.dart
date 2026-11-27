import 'package:drift/native.dart';
import 'package:fitness_tracker/app/providers.dart';
import 'package:fitness_tracker/app/theme.dart';
import 'package:fitness_tracker/core/database/database.dart'
    show TrackerDatabase;
import 'package:fitness_tracker/core/database/tracker_repository.dart';
import 'package:fitness_tracker/features/history/history_page.dart';
import 'package:fitness_tracker/shared/domain/training.dart';
import 'package:fitness_tracker/shared/widgets/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets(
    'repeat keeps every entry and measurement editable and saves fresh records',
    (tester) async {
      final now = DateTime(2026, 11, 13, 12);
      final today = CalendarDay.fromDate(now);
      final sourceDay = today.plusDays(-1);
      final repo = TrackerRepository(
        TrackerDatabase(NativeDatabase.memory()),
        now: () => now,
      );
      final repetitions = await repo.createExercise(
        'Push-ups',
        Measurement.repetitions,
        trackSets: true,
      );
      final duration = await repo.createExercise(
        'Plank',
        Measurement.duration,
        trackSets: true,
      );
      final weight = await repo.createExercise(
        'Deadlift',
        Measurement.weight,
        trackSets: true,
      );
      final weightAndReps = await repo.createExercise(
        'Bench press',
        Measurement.weightAndReps,
        trackSets: true,
      );
      final archived = await repo.createExercise(
        'Archived press',
        Measurement.repetitions,
      );
      await repo.log([
        EntryDraft(
          exerciseId: repetitions.id,
          day: sourceDay,
          notes: 'Old workout note',
          sets: [
            (id: null, value: 10, reps: null),
            (id: null, value: 8, reps: null),
          ],
        ),
        EntryDraft(
          exerciseId: repetitions.id,
          day: sourceDay,
          sets: [(id: null, value: 7, reps: null)],
        ),
        EntryDraft(
          exerciseId: duration.id,
          day: sourceDay,
          sets: [
            (id: null, value: 90, reps: null),
            (id: null, value: 60, reps: null),
          ],
        ),
        EntryDraft(
          exerciseId: weight.id,
          day: sourceDay,
          sets: [
            (id: null, value: 50000, reps: null),
            (id: null, value: 55000, reps: null),
          ],
        ),
        EntryDraft(
          exerciseId: weightAndReps.id,
          day: sourceDay,
          sets: [
            (id: null, value: 60000, reps: 8),
            (id: null, value: 65000, reps: 6),
          ],
        ),
        EntryDraft(
          exerciseId: archived.id,
          day: sourceDay,
          sets: [(id: null, value: 5, reps: null)],
        ),
        for (var i = 0; i < 18; i++)
          EntryDraft(
            exerciseId: repetitions.id,
            day: sourceDay,
            sets: [(id: null, value: 30 + i, reps: null)],
          ),
      ]);
      await repo.setArchived(archived.id, true);

      final original = await repo.snapshot();
      final allDay =
          (await repo.watchEntries(day: sourceDay, includeArchived: true).first)
              .toList()
            ..sort((a, b) => a.order.compareTo(b.order));
      expect(allDay, hasLength(24));
      expect((await repo.watchEntries(day: sourceDay).first), hasLength(23));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repo),
            nowProvider.overrideWithValue(() => now),
          ],
          child: MaterialApp(
            theme: trackerTheme(Brightness.light),
            home: const Scaffold(body: HistoryPage()),
          ),
        ),
      );
      try {
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Search history'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'not a match');
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel('12 Nov 2026, has records'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('All exercises'));
        await tester.tap(find.text('All exercises'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bench press').last);
        await tester.pumpAndSettle();
        expect(find.text('No matches'), findsOneWidget);
        await tester.ensureVisible(find.byTooltip('Day actions'));
        await tester.tap(find.byTooltip('Day actions'));
        await tester.pumpAndSettle();
        expect(find.text('Repeat workout'), findsOneWidget);
        await tester.tap(find.text('Repeat workout'));
        await tester.pumpAndSettle();
        expect(find.text('Repeat workout'), findsOneWidget);
        expect(
          find.text('From 12 Nov 2026 · 4 exercises · 27 sets'),
          findsOneWidget,
        );
        expect(
          find.text(
            '1 archived entry was skipped. Unarchive them to include them.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Old workout note'), findsNothing);

        final firstField = tester.widget<LargeNumberField>(
          find.byType(LargeNumberField).first,
        );
        expect(firstField.controller.text, '8');
        expect(firstField.focusNode!.hasFocus, isFalse);

        await tester.enterText(find.byType(TextFormField).first, '11');
        await tester.tap(find.text('Save 27 sets'));
        await tester.pumpAndSettle();

        final saved = await repo.snapshot();
        final originalEntryIds = original.entries
            .map((entry) => entry.id)
            .toSet();
        final originalSetIds = {
          for (final entry in original.entries)
            for (final set in entry.sets) set.id,
        };
        final repeated =
            saved.entries
                .where((entry) => !originalEntryIds.contains(entry.id))
                .toList()
              ..sort((a, b) => a.order.compareTo(b.order));
        expect(repeated, hasLength(23));
        expect(repeated.take(5).map((entry) => entry.exerciseId), [
          repetitions.id,
          repetitions.id,
          duration.id,
          weight.id,
          weightAndReps.id,
        ]);
        expect(
          repeated.skip(5).map((entry) => entry.exerciseId),
          everyElement(repetitions.id),
        );
        expect(repeated.map((entry) => entry.day), everyElement(today));
        expect(repeated.map((entry) => entry.notes), everyElement(isNull));
        expect(repeated.first.sets.map((set) => set.value), [10, 11]);
        expect(repeated[1].sets.single.value, 7);
        expect(repeated[2].sets.map((set) => set.value), [90, 60]);
        expect(repeated[3].sets.map((set) => set.value), [50000, 55000]);
        expect(repeated[4].sets.map((set) => (set.value, set.reps)), [
          (60000, 8),
          (65000, 6),
        ]);
        expect(
          repeated
              .expand((entry) => entry.sets)
              .every((set) => !originalSetIds.contains(set.id)),
          isTrue,
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await repo.close();
      }
    },
  );
}
