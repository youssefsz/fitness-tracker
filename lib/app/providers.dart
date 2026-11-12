import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/local_database.dart';
import '../core/database/tracker_repository.dart';
import '../core/platform/device_services.dart';
import '../shared/domain/training.dart';

final nowProvider = Provider<DateTime Function()>((ref) => DateTime.now);
final feedbackProvider = Provider<FeedbackService>(
  (ref) => const DeviceFeedback(),
);
final filesProvider = Provider<TransferFiles>(
  (ref) => const DeviceTransferFiles(),
);

final repositoryProvider = Provider<TrackerRepository>((ref) {
  final repo = TrackerRepository(
    openLocalDatabase(),
    now: ref.watch(nowProvider),
  );
  ref.onDispose(() => unawaited(repo.close()));
  return repo;
});

final bootstrapProvider = FutureProvider<void>(
  (ref) =>
      ref.watch(repositoryProvider).open().timeout(const Duration(seconds: 10)),
  retry: (_, _) => null,
);
final preferencesProvider = StreamProvider<Preferences>(
  (ref) => ref.watch(repositoryProvider).watchPreferences(),
);
final catalogProvider = StreamProvider<List<CatalogItem>>(
  (ref) => ref.watch(repositoryProvider).watchCatalog(),
);
final overviewProvider = StreamProvider.autoDispose<OverviewData>(
  (ref) => ref.watch(repositoryProvider).watchOverview(),
);

typedef EntriesFilter = ({
  String? exercise,
  CalendarDay? day,
  int limit,
  int offset,
  String search,
});
typedef CalendarFilter = ({
  CalendarDay start,
  CalendarDay end,
  String? exercise,
});

final entriesProvider = StreamProvider.autoDispose
    .family<List<Entry>, EntriesFilter>(
      (ref, filter) => ref
          .watch(repositoryProvider)
          .watchEntries(
            exerciseId: filter.exercise,
            day: filter.day,
            limit: filter.limit,
            offset: filter.offset,
            search: filter.search,
          ),
    );
final calendarProvider = StreamProvider.autoDispose
    .family<Set<CalendarDay>, CalendarFilter>(
      (ref, filter) => ref
          .watch(repositoryProvider)
          .watchRecordedDays(
            start: filter.start,
            end: filter.end,
            exerciseId: filter.exercise,
          ),
    );
final performanceProvider = StreamProvider.autoDispose
    .family<Performance, (String, DayRange)>(
      (ref, filter) =>
          ref.watch(repositoryProvider).watchPerformance(filter.$1, filter.$2),
    );
final goalProvider = StreamProvider.autoDispose.family<Goal?, String>(
  (ref, id) => ref.watch(repositoryProvider).watchGoal(id),
);
final durationProvider = Provider<DurationStyle>(
  (ref) => ref.watch(
    preferencesProvider.select(
      (value) => value.value?.duration ?? defaultPreferences.duration,
    ),
  ),
);

final todayProvider = NotifierProvider<LocalDay, CalendarDay>(LocalDay.new);

class LocalDay extends Notifier<CalendarDay> {
  @override
  CalendarDay build() {
    final now = ref.watch(nowProvider);
    Timer? timer;
    void schedule() {
      timer?.cancel();
      final current = now();
      final midnight = DateTime(current.year, current.month, current.day + 1);
      timer = Timer(
        midnight.difference(current) + const Duration(milliseconds: 50),
        refresh,
      );
    }

    final lifecycle = AppLifecycleListener(onResume: refresh);
    schedule();
    ref.onDispose(() {
      timer?.cancel();
      lifecycle.dispose();
    });
    _schedule = schedule;
    return CalendarDay.fromDate(now());
  }

  void Function()? _schedule;

  void refresh() {
    final today = CalendarDay.fromDate(ref.read(nowProvider)());
    if (state != today) state = today;
    _schedule?.call();
  }
}

final actionsProvider = Provider<TrainingActions>(
  (ref) => TrainingActions(
    ref.watch(repositoryProvider),
    ref.watch(feedbackProvider),
    () =>
        ref.read(preferencesProvider).value?.haptics ??
        defaultPreferences.haptics,
  ),
);

class TrainingActions {
  const TrainingActions(this.repository, this.feedback, this.hapticsEnabled);
  final TrackerRepository repository;
  final FeedbackService feedback;
  final bool Function() hapticsEnabled;

  Future<void> log(List<EntryDraft> drafts, {Entry? original}) async {
    final enabled = hapticsEnabled();
    if (original == null) {
      await repository.log(drafts);
    } else {
      await repository.updateEntry(original, drafts.single);
    }
    if (enabled) unawaited(_feedback(feedback.saved));
  }

  void select() {
    if (hapticsEnabled()) unawaited(_feedback(feedback.selection));
  }

  Future<void> _feedback(Future<void> Function() send) async {
    try {
      await send();
    } on Exception {
      // Unsupported feedback must never turn a committed save into a failure.
    }
  }
}
