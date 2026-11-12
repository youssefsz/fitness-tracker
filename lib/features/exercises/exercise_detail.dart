import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../shared/domain/training.dart';
import '../../shared/widgets/ui.dart';
import '../goals/goal_page.dart';
import '../history/entry_row.dart';
import '../logging/log_page.dart';
import '../progress/date_range_page.dart';
import '../progress/performance_chart.dart';
import '../progress/progress_page.dart';
import 'exercise_library.dart';

class ExerciseDetail extends ConsumerStatefulWidget {
  const ExerciseDetail({required this.id, super.key});
  final String id;

  @override
  ConsumerState<ExerciseDetail> createState() => _ExerciseDetailState();
}

class _ExerciseDetailState extends ConsumerState<ExerciseDetail> {
  RangeSelection _range = allTime;
  static const _pageSize = 12;
  int _page = 0;
  final _entryHeading = GlobalKey();

  void _goToPage(int page) {
    setState(() => _page = page);
    final heading = _entryHeading.currentContext;
    if (heading != null) Scrollable.ensureVisible(heading);
  }

  bool _busy = false, _confirming = false;

  Future<void> _archive(Exercise exercise) async {
    if (_busy || _confirming) return;
    try {
      if (!exercise.archived) {
        _confirming = true;
        final confirm = await confirmAction(
          context,
          title: 'Archive ${exercise.name}?',
          message: 'You can still see its history and restore it later.',
          label: 'Archive',
        );
        _confirming = false;
        if (!mounted || !confirm) return;
      }
      setState(() => _busy = true);
      await ref
          .read(repositoryProvider)
          .setArchived(exercise.id, !exercise.archived);
      if (mounted) {
        announce(
          context,
          exercise.archived ? 'Exercise restored.' : 'Exercise archived.',
        );
      }
    } catch (error) {
      if (mounted) announce(context, describeError(error));
    } finally {
      _confirming = false;
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    final item = catalog.value
        ?.where((x) => x.exercise.id == widget.id)
        .firstOrNull;
    final exercise = item?.exercise;
    final today = ref.watch(todayProvider);
    final goal = goalProvider(widget.id);
    final all = performanceProvider((
      widget.id,
      allTime.preset.boundaries(today),
    ));
    final entries = entriesProvider((
      exercise: widget.id,
      day: null,
      limit: _pageSize + 1,
      offset: _page * _pageSize,
      search: '',
    ));
    final style = ref.watch(durationProvider);

    return Scaffold(
      appBar: secondaryBar(
        context,
        actions: [
          if (exercise != null)
            PopupMenuButton<String>(
              tooltip: 'Exercise options',
              enabled: !_busy,
              icon: const Icon(LucideIcons.ellipsis, size: 20),
              onSelected: (choice) async {
                if (choice == 'edit') {
                  try {
                    final existing = await ref.read(goal.future);
                    if (context.mounted) {
                      await openExerciseEditor(
                        context,
                        item: item,
                        hasGoal: existing != null,
                      );
                    }
                  } catch (error) {
                    if (context.mounted) {
                      announce(context, describeError(error));
                    }
                  }
                } else {
                  await _archive(exercise);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Text('Edit exercise'),
                ),
                PopupMenuItem(
                  value: 'archive',
                  child: Text(
                    exercise.archived ? 'Restore exercise' : 'Archive exercise',
                  ),
                ),
              ],
            ),
        ],
      ),
      body: ScreenScroll(
        width: 1100,
        children: [
          AsyncPanel(
            catalog,
            retry: () => ref.invalidate(catalogProvider),
            builder: (_) {
              if (exercise == null) {
                return const EmptyBlock(
                  title: 'Exercise unavailable',
                  message: 'It may have been replaced by a backup restore.',
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ScreenHeading(
                    exercise.name,
                    top: 0,
                    subtitle:
                        '${exercise.measurement.label}${exercise.archived ? ' · Archived' : ''}',
                  ),
                  FilterButton(_range.preset.label, () async {
                    final selected = await selectRange(context, _range, today);
                    if (mounted && selected != null) {
                      setState(() => _range = selected);
                    }
                  }),
                  const SizedBox(height: 12),
                  PerformanceView(
                    exercise: exercise,
                    range: selectionBounds(_range, today),
                    volume: false,
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  AsyncPanel(
                    ref.watch(goal),
                    retry: () => ref.invalidate(goal),
                    builder: (g) => AsyncPanel(
                      ref.watch(all),
                      retry: () => ref.invalidate(all),
                      builder: (data) => GoalSummary(
                        exercise: exercise,
                        goal: g,
                        data: data,
                        today: today,
                        durationStyle: style,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 14),
                  SectionTitle('Recorded sets', key: _entryHeading),
                  AsyncPanel(
                    ref.watch(entries),
                    retry: () => ref.invalidate(entries),
                    builder: (records) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (records.isEmpty)
                          Text(
                            'No entries yet.',
                            style: context.type.bodySmall,
                          ),
                        for (final record in records.take(_pageSize))
                          EntryRow(
                            key: ValueKey(record.id),
                            entry: record,
                            exercise: exercise,
                            showDate: true,
                          ),
                        Wrap(
                          spacing: 8,
                          children: [
                            if (_page > 0)
                              QuietButton(
                                'Newer entries',
                                () => _goToPage(_page - 1),
                              ),
                            if (records.length > _pageSize)
                              QuietButton(
                                'Older entries',
                                () => _goToPage(_page + 1),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: exercise == null
          ? null
          : KeyboardFooter(
              child: ActionFooter(
                label: exercise.archived ? 'Restore exercise' : 'Add entry',
                busy: _busy,
                onPressed: exercise.archived
                    ? () => _archive(exercise)
                    : () => context.push(
                        '/log',
                        extra: LogRequest(exercise: exercise),
                      ),
              ),
            ),
    );
  }
}
