import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/database/tracker_repository.dart';
import '../../shared/domain/training.dart';
import '../../shared/widgets/ui.dart';
import '../history/entry_row.dart';
import '../progress/performance_chart.dart';

class OverviewPage extends ConsumerWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    final value = ref.watch(overviewProvider);
    final style = ref.watch(durationProvider);
    return ScreenScroll(
      primary: true,
      width: 1100,
      scrollKey: const PageStorageKey('overview'),
      children: [
        ScreenHeading(
          'Overview',
          subtitle: value.value == null
              ? null
              : value.value!.exercises.isEmpty
              ? 'No entries yet'
              : '${value.value!.exercises.length} ${value.value!.exercises.length == 1 ? 'exercise' : 'exercises'} · '
                    'Since ${fullDay(value.value!.firstDay!)}',
          action: RoundControl(
            LucideIcons.settings,
            'Settings',
            () => context.push('/settings'),
          ),
        ),
        AsyncPanel(
          value,
          retry: () => ref.invalidate(overviewProvider),
          builder: (data) {
            if (data.exercises.isEmpty) {
              return Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 445),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: (MediaQuery.sizeOf(context).height * .145)
                            .clamp(24.0, 118.0),
                      ),
                      Text(
                        'Start with one result.',
                        style: context.type.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Pick an exercise, enter your reps or time, and choose the date.',
                        style: context.type.bodyLarge?.copyWith(
                          color: context.colors.muted,
                        ),
                      ),
                      const SizedBox(height: 22),
                      FilledButton(
                        onPressed: () => context.push('/log'),
                        child: const Text('Record your first result'),
                      ),
                      const SizedBox(height: 4),
                      QuietButton(
                        'Import a backup',
                        () => context.push('/transfer/backup'),
                      ),
                      const SizedBox(height: 26),
                      Text(
                        'Log whenever you like. Your history starts with what you record.',
                        style: context.type.bodySmall,
                      ),
                    ],
                  ),
                ),
              );
            }
            return AsyncPanel(
              catalog,
              retry: () => ref.invalidate(catalogProvider),
              builder: (items) {
                final map = {
                  for (final row in items) row.exercise.id: row.exercise,
                };
                return ResponsiveSplit(
                  main: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionTitle(
                        'Your exercises',
                        action: QuietButton(
                          'Manage',
                          () => context.push('/exercises'),
                        ),
                      ),
                      for (final summary in data.exercises)
                        if (map[summary.exerciseId] case final exercise?)
                          _ExerciseSummary(
                            exercise: exercise,
                            summary: summary,
                            style: style,
                          ),
                    ],
                  ),
                  side: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionTitle(
                        'Recent activity',
                        action: QuietButton(
                          'View history',
                          () => context.go('/history'),
                        ),
                      ),
                      for (final entry in data.recent)
                        if (map[entry.exerciseId] case final exercise?)
                          EntryRow(
                            key: ValueKey(entry.id),
                            entry: entry,
                            exercise: exercise,
                            compact: true,
                            showDate: true,
                          ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _ExerciseSummary extends StatelessWidget {
  const _ExerciseSummary({
    required this.exercise,
    required this.summary,
    required this.style,
  });
  final Exercise exercise;
  final OverviewExercise summary;
  final DurationStyle style;

  @override
  Widget build(BuildContext context) {
    final measurement = exercise.measurement;
    final change = summary.latest - summary.first;
    final percent = (change / summary.first * 100).round();
    return Column(
      children: [
        Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => context.push('/exercise/${exercise.id}'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: LayoutBuilder(
                builder: (context, size) {
                  final identity = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(exercise.name, style: context.type.titleMedium),
                      const SizedBox(height: 3),
                      Text(
                        'Best ${measure(summary.best, measurement, style)} · First ${measure(summary.first, measurement, style)}',
                        style: context.type.bodySmall,
                      ),
                      if (exercise.archived)
                        Text('Archived', style: context.type.bodySmall),
                      if (summary.count > 1)
                        Text(
                          '${signed(percent)}% since first',
                          style: context.type.labelMedium?.copyWith(
                            color: change > 0
                                ? context.colors.green
                                : context.colors.muted,
                          ),
                        ),
                    ],
                  );
                  final latest = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            measure(summary.latest, measurement, style),
                            style: context.type.titleMedium,
                            semanticsLabel:
                                'Latest set: ${measure(summary.latest, measurement, style, accessible: true)}',
                          ),
                          Text(
                            shortDay(summary.latestDay),
                            style: context.type.bodySmall,
                          ),
                        ],
                      ),
                      if (summary.trend.length > 1) ...[
                        const SizedBox(height: 6),
                        Sparkline(summary.trend),
                      ],
                    ],
                  );
                  if (size.maxWidth < 300 &&
                      MediaQuery.textScalerOf(context).scale(16) > 22) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [identity, const SizedBox(height: 8), latest],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: identity),
                      const SizedBox(width: 12),
                      Expanded(flex: 4, child: latest),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        const Divider(),
      ],
    );
  }
}
