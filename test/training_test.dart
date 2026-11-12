import 'package:fitness_tracker/shared/domain/training.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('calendar dates retain days across leap years and daylight saving', () {
    final leap = CalendarDay.parse('2024-02-29');
    expect(leap.plusDays(1).iso, '2024-03-01');
    expect(CalendarDay.earliest.utc, DateTime.utc(1900));
    expect(
      CalendarDay.parse('2026-03-09')
          .daysSince(CalendarDay.parse('2026-03-07')),
      2,
    );
    for (final bad in [
      '2026-02-29',
      '2026-02-30',
      '2026-2-01',
      '2026-01-01T00:00Z',
    ]) {
      expect(() => CalendarDay.parse(bad), throwsFormatException);
    }
  });

  test(
    'rolling presets include today and the specified number of calendar days',
    () {
      final today = CalendarDay.parse('2026-11-12');
      for (final (preset, count) in [
        (RangePreset.week, 7),
        (RangePreset.month, 30),
        (RangePreset.quarter, 90),
        (RangePreset.year, 365),
      ]) {
        final range = preset.boundaries(today);
        expect(range.end, today);
        expect(range.end!.daysSince(range.start!) + 1, count);
      }
      expect(RangePreset.all.boundaries(today), (start: null, end: null));
    },
  );

  test(
    'empty and single performances omit comparison; declines stay negative',
    () {
      final date = CalendarDay.parse('2026-11-12');
      final one = (
        day: date,
        first: 12,
        latest: 12,
        best: 12,
        total: 12,
        count: 1,
      );
      final worse = (
        day: date.plusDays(1),
        first: 9,
        latest: 9,
        best: 9,
        total: 9,
        count: 1,
      );
      expect(Performance([]).latest, isNull);
      expect(Performance([]).total, 0);
      expect(Performance([one]).percent, isNull);
      expect(Performance([one, worse]).change, -3);
      expect(Performance([one, worse]).percent, -25);
      expect(
        Performance([
          (day: date, first: 0, latest: 0, best: 0, total: 0, count: 1),
          worse,
        ]).percent,
        isNull,
      );
    },
  );

  test(
    'deadline is inclusive and later records cannot satisfy an expired goal',
    () {
      final deadline = CalendarDay.parse('2026-11-12');
      final today = deadline.plusDays(2);
      final goal = Goal(
        exerciseId: 'exercise',
        target: 22,
        deadline: deadline,
        updatedAt: DateTime.utc(2026, 10, 1),
      );
      DailyResult day(CalendarDay day) =>
          (day: day, first: 22, latest: 18, best: 22, total: 60, count: 3);
      expect(goalStatus(goal, [day(deadline)], today), GoalStatus.achieved);
      expect(
        goalStatus(goal, [day(deadline.plusDays(1))], today),
        GoalStatus.expired,
      );
      expect(goalStatus(goal, [], deadline), GoalStatus.pending);
    },
  );

  test('durations format stored seconds without changing the unit', () {
    expect(clockValue(0), '0:00');
    expect(clockValue(65), '1:05');
    expect(clockValue(3601), '60:01');
    expect(measure(65, Measurement.duration, DurationStyle.seconds), '65 sec');
    expect(
      measure(65, Measurement.duration, DurationStyle.clock, accessible: true),
      '1 minute, 5 seconds',
    );
    expect(changeText(-65, Measurement.duration, DurationStyle.clock), '−1:05');
  });
}
