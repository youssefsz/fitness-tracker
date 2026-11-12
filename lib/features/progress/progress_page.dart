import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/database/tracker_repository.dart';
import '../../shared/domain/training.dart';
import '../../shared/widgets/ui.dart';
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
    final id = await chooseOption<String>(context, 'Choose exercise', [
      for (final row in list)
        (
          value: row.exercise.id,
          label: row.exercise.name,
          subtitle:
              '${row.exercise.measurement.label}${row.exercise.archived ? ' · Archived' : ''}',
        ),
    ], selected: current);
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
        const ScreenHeading('Progress'),
        AsyncPanel(
          ref.watch(catalogProvider),
          retry: () => ref.invalidate(catalogProvider),
          builder: (list) {
            if (list.isEmpty || !list.any((row) => row.count > 0)) {
              return EmptyBlock(
                title: 'See how your sets change',
                message: 'Record a result to see its first, latest, and best values here.',
                action: 'Add entry',
                onAction: () => context.push('/log'),
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
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterButton(
                      exercise.name,
                      () => _pickExercise(tracked, exercise.id),
                    ),
                    FilterButton(_range.preset.label, () async {
                      final range = await selectRange(context, _range, today);
                      if (mounted && range != null) {
                        ref.read(actionsProvider).select();
                        setState(() => _range = range);
                      }
                    }),
                  ],
                ),
                const SizedBox(height: 12),
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
    this.volume = true,
    super.key,
  });
  final Exercise exercise;
  final DayRange range;
  final bool link, volume;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = performanceProvider((exercise.id, range));
    final style = ref.watch(durationProvider);
    return AsyncPanel(
      ref.watch(provider),
      retry: () => ref.invalidate(provider),
      builder: (data) {
        if (data.days.isEmpty) {
          return const EmptyBlock(
            title: 'No sets in this range',
            message: 'Choose a wider date range or record another set.',
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
              main: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PerformanceSummary(
                    data: data,
                    measurement: exercise.measurement,
                    style: style,
                  ),
                  const Divider(),
                  const SizedBox(height: 15),
                  _PerformancePlot(
                    data: data,
                    measurement: exercise.measurement,
                    style: style,
                  ),
                ],
              ),
              side: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatLine(
                    data: data,
                    measurement: exercise.measurement,
                    style: style,
                  ),
                  if (volume) ...[
                    const SizedBox(height: 18),
                    const Divider(),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 18,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          'Total volume',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 19,
                          ),
                        ),
                        Text(
                          measure(data.total, exercise.measurement, style),
                          style: context.type.titleMedium,
                        ),
                      ],
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
                  ],
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
  });
  final Performance data;
  final Measurement measurement;
  final DurationStyle style;

  @override
  ConsumerState<_PerformancePlot> createState() => _PerformancePlotState();
}

class _PerformancePlotState extends ConsumerState<_PerformancePlot> {
  ChartMetric _metric = ChartMetric.latest;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SectionTitle('Performance'),
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
