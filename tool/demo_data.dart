import 'dart:math';

import 'package:fitness_tracker/shared/domain/training.dart';

const _training = [
  (
    key: 'push',
    name: 'Push-ups',
    measurement: Measurement.repetitions,
    initial: 12,
    gain: 20,
    target: 38,
  ),
  (
    key: 'pull',
    name: 'Pull-ups',
    measurement: Measurement.repetitions,
    initial: 3,
    gain: 8,
    target: 16,
  ),
  (
    key: 'plank',
    name: 'Plank',
    measurement: Measurement.duration,
    initial: 45,
    gain: 100,
    target: 120,
  ),
  (
    key: 'squat',
    name: 'Bodyweight squats',
    measurement: Measurement.repetitions,
    initial: 16,
    gain: 22,
    target: 42,
  ),
  (
    key: 'wall',
    name: 'Wall sit',
    measurement: Measurement.duration,
    initial: 35,
    gain: 74,
    target: 120,
  ),
  (
    key: 'hollow',
    name: 'Hollow hold',
    measurement: Measurement.duration,
    initial: 20,
    gain: 34,
    target: 0,
  ),
];

BackupData demoData(CalendarDay today) {
  final random = Random(411);
  const span = 244;
  final first = today.plusDays(-span);
  final created = first.utc.add(const Duration(hours: 9));
  final exercises = [
    for (final x in _training)
      Exercise(
        id: 'v-demo-${x.key}',
        name: x.name,
        measurement: x.measurement,
        archived: x.key == 'hollow',
        createdAt: created,
        updatedAt: x.key == 'hollow' ? today.plusDays(-65).utc : created,
      ),
  ];
  final entries = <Entry>[];
  final goals = <Goal>[];
  for (var i = 0; i <= span; i++) {
    final day = first.plusDays(i);
    // Weekly patterns, a trip, and occasional short sessions.
    final finalSession = i == span;
    final weekday = day.utc.weekday;
    if (!finalSession &&
        (i >= 92 && i <= 103 ||
            ![
              DateTime.monday,
              DateTime.wednesday,
              DateTime.friday,
              DateTime.sunday,
            ].contains(weekday) ||
            random.nextInt(10) == 0)) {
      continue;
    }
    for (final (index, x) in _training.indexed) {
      if (x.key == 'hollow' && i > span - 65) continue;
      if (!finalSession && index > 0 && (i + index) % 4 == 0) continue;
      if (finalSession && index > 3) continue;
      final variation = x.measurement == Measurement.duration ? 18 : 6;
      final slump = i > 145 && i < 170 ? variation ~/ 2 : 0;
      final center = x.initial + (x.gain * i / span).round() - slump;
      final peak = max(1, center + random.nextInt(variation) - variation ~/ 2);
      final count = x.key == 'push'
          ? 3 + random.nextInt(2)
          : 2 + random.nextInt(3);
      final order = entries.length + 1;
      final time = day.utc.add(
        Duration(hours: finalSession ? 8 : 16, minutes: index * 5),
      );
      final notes = random.nextInt(7) == 0
          ? const [
              'Kept the tempo steady.',
              'Short session today.',
              'Took a longer rest between sets.',
              'Last set felt harder.',
            ][random.nextInt(4)]
          : null;
      entries.add(
        Entry(
          id: 'v-demo-entry-$order',
          exerciseId: 'v-demo-${x.key}',
          day: day,
          notes: notes,
          order: order,
          createdAt: time,
          updatedAt: time,
          sets: [
            for (var s = 0; s < count; s++)
              (
                id: 'v-demo-set-$order-$s',
                position: s,
                reps: null,
                value: max(
                  1,
                  peak -
                      s * max(1, variation ~/ 5) +
                      (s == 0 ? 0 : random.nextInt(3) - 1),
                ).toInt(),
              ),
          ],
        ),
      );
    }
    if (i % 37 == 0) {
      final order = entries.length + 1;
      final time = day.utc.add(const Duration(hours: 20));
      entries.add(
        Entry(
          id: 'v-demo-entry-$order',
          exerciseId: 'v-demo-push',
          day: day,
          notes: 'One extra set later that day.',
          order: order,
          createdAt: time,
          updatedAt: time,
          sets: [
            (
              id: 'v-demo-set-$order-0',
              position: 0,
              value: 8 + i ~/ 17,
              reps: null,
            ),
          ],
        ),
      );
    }
  }
  for (final x in _training.where((x) => x.target > 0)) {
    goals.add(
      Goal(
        exerciseId: 'v-demo-${x.key}',
        target: x.target,
        deadline: x.key == 'pull'
            ? today.plusDays(-20)
            : x.key == 'squat'
            ? today.plusDays(40)
            : null,
        updatedAt: today.plusDays(-48).utc,
      ),
    );
  }
  return BackupData(
    exercises: exercises,
    entries: entries,
    goals: goals,
    preferences: defaultPreferences,
    receipts: {},
  );
}
