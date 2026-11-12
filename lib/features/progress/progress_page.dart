import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/database/tracker_repository.dart';
import '../../shared/domain/training.dart';
import '../../shared/widgets/exercise_icon.dart';
import '../../shared/widgets/ui.dart';
import '../logging/log_page.dart';
import 'date_range_page.dart';
import 'performance_chart.dart';

class ProgressPage extends ConsumerStatefulWidget {
  const ProgressPage({super.key});

  @override
  ConsumerState<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends ConsumerState<ProgressPage> {
  String? _exercise;
  RangeSelection _range = allTime;

  Future<void> _pickExercise(List<CatalogItem> list, String current) async {
    final id = await chooseOption<String>(
      context,
      'Choose exercise',
      [
        for (final row in list)
          (
            value: row.exercise.id,
            label: row.exercise.name,
            subtitle:
                '${row.exercise.measurement.label}${row.exercise.archived ? ' · Archived' : ''}',
          ),
      ],
      selected: current,
      leading: (_, name) => ExerciseIcon(name),
    );
    if (!mounted || id == null || id == current) return;
    ref.read(actionsProvider).select();
    setState(() => _exercise = id);
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayProvider);
    return ScreenScroll(
      primary: true,
      width: 1100,
      scrollKey: const PageStorageKey('progress'),
      children: [
        const ScreenHeading('Progress', bottom: Space.xs),
        AsyncPanel(
          ref.watch(catalogProvider),
          retry: () => ref.invalidate(catalogProvider),
          builder: (list) {
            if (list.isEmpty || !list.any((row) => row.count > 0)) {
              return EmptyBlock(
                title: 'See how your sets change',
                message: 'Record a result to see its first, latest, and best values here.',
                action: 'Add entry',
                onAction: () => showLogSheet(context),
              );
            }
            final tracked = list.where((row) => row.count > 0).toList();
            final exercise =
                (tracked
                            .where((row) => row.exercise.id == _exercise)
                            .firstOrNull ??
                        tracked.first)
                    .exercise;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FilterButton(
                  exercise.name,
                  () => _pickExercise(tracked, exercise.id),
                  leading: ExerciseIcon(exercise.name),
                  prominent: true,
                ),
                FilterButton(_range.preset.label, () async {
                  final range = await selectRange(context, _range, today);
                  if (mounted && range != null) {
                    ref.read(actionsProvider).select();
                    setState(() => _range = range);
                  }
                }),
                PerformanceView(
                  key: ValueKey(exercise.id),
                  exercise: exercise,
                  range: selectionBounds(_range, today),
                  link: true,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class PerformanceView extends ConsumerWidget {
  const PerformanceView({
    required this.exercise,
    required this.range,
    this.link = false,
    this.rangeAction,
    super.key,
  });
  final Exercise exercise;
  final DayRange range;
  final bool link;
  final Widget? rangeAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = performanceProvider((exercise.id, range));
    final style = ref.watch(durationProvider);
    return AsyncPanel(
      ref.watch(provider),
      retry: () => ref.invalidate(provider),
      builder: (data) {
        if (data.days.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (rangeAction != null)
                SectionTitle('Performance', action: rangeAction),
              const EmptyBlock(
                title: 'No sets in this range',
                message: 'Choose a wider date range or record another set.',
              ),
            ],
          );
        }
        final summary = PerformanceSummary(
          data: data,
          measurement: exercise.measurement,
          style: style,
        );
        final stats = _StatLine(
          data: data,
          measurement: exercise.measurement,
          style: style,
        );
        final plot = _PerformancePlot(
          data: data,
          measurement: exercise.measurement,
          style: style,
          rangeAction: rangeAction,
        );
        if (rangeAction != null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              summary,
              const Divider(),
              const SizedBox(height: Space.md),
              stats,
              const SizedBox(height: Space.md),
              const Divider(),
              const SizedBox(height: Space.sm),
              plot,
            ],
          );
        }
        final first = range.start ?? data.firstDay!;
        final last = range.end ?? data.latestDay!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              first == last
                  ? fullDay(first)
                  : '${fullDay(first)} to ${fullDay(last)}',
              style: context.type.bodySmall,
            ),
            const SizedBox(height: 14),
            ResponsiveSplit(
              stackGap: Space.md,
              main: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  summary,
                  const Divider(),
                  const SizedBox(height: 15),
                  plot,
                ],
              ),
              side: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  stats,
                  const SizedBox(height: 18),
                  const Divider(),
                  const SizedBox(height: 14),
                  SectionTitle(
                    'Total volume',
                    action: Text(
                      measure(data.total, exercise.measurement, style),
                      style: context.type.titleMedium,
                      textAlign: TextAlign.end,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${data.setCount} ${data.setCount == 1 ? 'set' : 'sets'} across ${data.days.length} '
                    '${data.days.length == 1 ? 'recorded date' : 'recorded dates'}',
                    style: context.type.bodySmall,
                  ),
                  PerformanceChart(
                    days: data.days,
                    metric: ChartMetric.volume,
                    measurement: exercise.measurement,
                    durationStyle: style,
                  ),
                  if (link)
                    QuietButton(
                      'View exercise details',
                      () => context.push('/exercise/${exercise.id}'),
                      icon: LucideIcons.arrowUpRight,
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class PerformanceSummary extends StatelessWidget {
  const PerformanceSummary({
    required this.data,
    required this.measurement,
    required this.style,
    super.key,
  });
  final Performance data;
  final Measurement measurement;
  final DurationStyle style;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Wrap(
      spacing: 26,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              measure(data.latest!, measurement, style),
              style: context.type.headlineMedium,
            ),
            Text(
              'Latest set · ${shortDay(data.latestDay!)}',
              style: context.type.bodySmall,
            ),
          ],
        ),
        if (data.change case final delta?)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [
                  changeText(delta, measurement, style),
                  if (data.percent case final percent?)
                    '${signed(percent.round())}%',
                ].join(' · '),
                style: context.type.titleMedium?.copyWith(
                  color: delta > 0 ? context.colors.green : context.colors.ink,
                ),
              ),
              Text('vs first recorded set', style: context.type.bodySmall),
            ],
          )
        else
          Text('Not enough history to compare.', style: context.type.bodySmall),
      ],
    ),
  );
}

class _StatLine extends StatelessWidget {
  const _StatLine({
    required this.data,
    required this.measurement,
    required this.style,
  });
  final Performance data;
  final Measurement measurement;
  final DurationStyle style;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 28,
    runSpacing: 12,
    children: [
      for (final (label, value) in [
        ('First', data.first!),
        ('Latest', data.latest!),
        ('Best', data.best!),
      ])
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: context.type.bodySmall),
            Text(
              measure(value, measurement, style),
              style: context.type.titleMedium,
            ),
          ],
        ),
    ],
  );
}

class _PerformancePlot extends ConsumerStatefulWidget {
  const _PerformancePlot({
    required this.data,
    required this.measurement,
    required this.style,
    this.rangeAction,
  });
  final Performance data;
  final Measurement measurement;
  final DurationStyle style;
  final Widget? rangeAction;

  @override
  ConsumerState<_PerformancePlot> createState() => _PerformancePlotState();
}

class _PerformancePlotState extends ConsumerState<_PerformancePlot> {
  ChartMetric _metric = ChartMetric.latest;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SectionTitle('Performance', action: widget.rangeAction),
      MetricTabs(
        selected: _metric,
        onChanged: (metric) {
          if (_metric == metric) return;
          ref.read(actionsProvider).select();
          setState(() => _metric = metric);
        },
      ),
      PerformanceChart(
        days: widget.data.days,
        metric: _metric,
        measurement: widget.measurement,
        durationStyle: widget.style,
      ),
    ],
  );
}
