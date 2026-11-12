import 'dart:math' as math;

const maxSetValue = 999999;
const maxEntryOrder = 9007199254740991;
const maxSetsPerEntry = 100;
const maxExerciseName = 80;
const maxNotes = 2000;

final class CalendarDay implements Comparable<CalendarDay> {
  const CalendarDay._(this.iso, this._epochDay);

  factory CalendarDay.fromDate(DateTime date) => CalendarDay._(
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}',
    DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch ~/
        _dayMilliseconds,
  );

  factory CalendarDay.parse(String input) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(input)) {
      throw const FormatException('Use a date in YYYY-MM-DD format.');
    }
    final date = DateTime.tryParse('${input}T00:00:00Z');
    if (date == null ||
        date.year < 1900 ||
        CalendarDay.fromDate(date).iso != input) {
      throw const FormatException(
        'Enter a valid calendar date from 1900 onward.',
      );
    }
    return CalendarDay._(
      input,
      date.millisecondsSinceEpoch ~/ _dayMilliseconds,
    );
  }

  static const earliest = CalendarDay._('1900-01-01', -25567);
  static const _dayMilliseconds = Duration.millisecondsPerDay;
  final int _epochDay;
  final String iso;

  DateTime get utc => DateTime.fromMillisecondsSinceEpoch(
    _epochDay * _dayMilliseconds,
    isUtc: true,
  );
  DateTime get local => DateTime(utc.year, utc.month, utc.day);
  CalendarDay plusDays(int count) =>
      CalendarDay.fromDate(utc.add(Duration(days: count)));
  int daysSince(CalendarDay other) => _epochDay - other._epochDay;
  bool isAfter(CalendarDay other) => compareTo(other) > 0;
  bool isBefore(CalendarDay other) => compareTo(other) < 0;

  @override
  int compareTo(CalendarDay other) => iso.compareTo(other.iso);
  @override
  bool operator ==(Object other) => other is CalendarDay && iso == other.iso;
  @override
  int get hashCode => iso.hashCode;
  @override
  String toString() => iso;
}

typedef DayRange = ({CalendarDay? start, CalendarDay? end});

enum RangePreset {
  week('Last 7 days'),
  month('Last 30 days'),
  quarter('Last 90 days'),
  year('Last year'),
  all('All time'),
  custom('Custom range');

  const RangePreset(this.label);
  final String label;

  DayRange boundaries(CalendarDay today) => switch (this) {
    week => (start: today.plusDays(-6), end: today),
    month => (start: today.plusDays(-29), end: today),
    quarter => (start: today.plusDays(-89), end: today),
    year => (start: today.plusDays(-364), end: today),
    all => (start: null, end: null),
    custom => throw StateError('Custom dates must be supplied.'),
  };
}

enum Measurement {
  repetitions('Repetitions', 'reps'),
  duration('Duration', 'seconds');

  const Measurement(this.label, this.unit);
  final String label;
  final String unit;
}

enum DurationStyle { clock, seconds }

enum Appearance { system, light, dark }

typedef Preferences = ({
  Appearance appearance,
  DurationStyle duration,
  bool haptics,
});

const defaultPreferences = (
  appearance: Appearance.system,
  duration: DurationStyle.clock,
  haptics: true,
);

String clockValue(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

String measureValue(int value, Measurement measurement, DurationStyle style) =>
    measurement == Measurement.duration && style == DurationStyle.clock
    ? clockValue(value)
    : '$value';

String measure(
  int value,
  Measurement measurement,
  DurationStyle style, {
  bool accessible = false,
}) {
  if (measurement == Measurement.repetitions) {
    return '$value ${value == 1 ? 'rep' : 'reps'}';
  }
  if (style == DurationStyle.seconds) return '$value sec';
  if (accessible) {
    final minutes = value ~/ 60, seconds = value % 60;
    return '$minutes ${minutes == 1 ? 'minute' : 'minutes'}, $seconds ${seconds == 1 ? 'second' : 'seconds'}';
  }
  return clockValue(value);
}

String signed(int value) => value < 0 ? '−${value.abs()}' : '+$value';

String changeText(int value, Measurement measurement, DurationStyle style) =>
    '${value < 0 ? '−' : '+'}${measure(value.abs(), measurement, style)}';

String normalizeName(String name) =>
    name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

String? exerciseNameError(String name) {
  if (name.trim().isEmpty) return 'Enter an exercise name.';
  if (name.trim().length > maxExerciseName) {
    return 'Use $maxExerciseName characters or fewer.';
  }
  if (name.contains(RegExp(r'[\x00-\x1f\x7f]'))) return 'Use a single line.';
  return null;
}

String? setValueError(int? value) =>
    value == null || value < 1 || value > maxSetValue
    ? 'Enter a whole number from 1 to $maxSetValue.'
    : null;

class TrackerException implements Exception {
  const TrackerException(this.message);
  final String message;
  @override
  String toString() => message;
}

class Exercise {
  const Exercise({
    required this.id,
    required this.name,
    required this.measurement,
    required this.archived,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id;
  final String name;
  final Measurement measurement;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;
}

typedef RecordedSet = ({String id, int position, int value});

class Entry {
  Entry({
    required this.id,
    required this.exerciseId,
    required this.day,
    required this.notes,
    required this.order,
    required this.createdAt,
    required this.updatedAt,
    required Iterable<RecordedSet> sets,
  }) : sets = List.unmodifiable(sets);
  final String id;
  final String exerciseId;
  final CalendarDay day;
  final String? notes;
  final int order;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<RecordedSet> sets;
  int get total => sets.fold(0, (sum, set) => sum + set.value);
  int get latest => sets.last.value;
  int get best => sets.map((set) => set.value).reduce(math.max);
}

typedef DraftSet = ({String? id, int value});

class EntryDraft {
  EntryDraft({
    required this.exerciseId,
    required this.day,
    this.notes,
    required Iterable<DraftSet> sets,
  }) : sets = List.unmodifiable(sets);
  final String exerciseId;
  final CalendarDay day;
  final String? notes;
  final List<DraftSet> sets;
}

class Goal {
  const Goal({
    required this.exerciseId,
    required this.target,
    required this.deadline,
    required this.updatedAt,
  });
  final String exerciseId;
  final int target;
  final CalendarDay? deadline;
  final DateTime updatedAt;
}

enum GoalStatus { pending, achieved, expired }

GoalStatus goalStatus(
  Goal goal,
  Iterable<DailyResult> days,
  CalendarDay today,
) {
  final achieved = days.any(
    (d) =>
        d.best >= goal.target &&
        !d.day.isAfter(today) &&
        (goal.deadline == null || !d.day.isAfter(goal.deadline!)),
  );
  if (achieved) return GoalStatus.achieved;
  if (goal.deadline case final deadline? when today.isAfter(deadline)) {
    return GoalStatus.expired;
  }
  return GoalStatus.pending;
}

typedef DailyResult = ({
  CalendarDay day,
  int first,
  int latest,
  int best,
  int total,
  int count,
});

class Performance {
  Performance(Iterable<DailyResult> results)
    : days = List.unmodifiable(results) {
    var best = 0, total = 0, count = 0;
    for (final day in days) {
      best = math.max(best, day.best);
      total += day.total;
      count += day.count;
    }
    this.best = days.isEmpty ? null : best;
    this.total = total;
    setCount = count;
  }
  final List<DailyResult> days;
  late final int? best;
  late final int total;
  late final int setCount;
  CalendarDay? get firstDay => days.firstOrNull?.day;
  CalendarDay? get latestDay => days.lastOrNull?.day;
  int? get first => days.firstOrNull?.first;
  int? get latest => days.lastOrNull?.latest;
  int? get change => setCount < 2 ? null : latest! - first!;
  double? get percent =>
      change == null || first == 0 ? null : change! / first! * 100;
}

class BackupData {
  BackupData({
    required Iterable<Exercise> exercises,
    required Iterable<Entry> entries,
    required Iterable<Goal> goals,
    required this.preferences,
    required Map<String, DateTime> receipts,
  }) : exercises = List.unmodifiable(exercises),
       entries = List.unmodifiable(entries),
       goals = List.unmodifiable(goals),
       receipts = Map.unmodifiable(receipts);
  final List<Exercise> exercises;
  final List<Entry> entries;
  final List<Goal> goals;
  final Preferences preferences;
  final Map<String, DateTime> receipts;
}

typedef BackupWrite = ({BackupData data, bool replace});
typedef NewExerciseSpec = ({String key, String name, Measurement measurement});
typedef ActivityWrite = ({
  List<NewExerciseSpec> create,
  List<EntryDraft> entries,
  String fingerprint,
});
