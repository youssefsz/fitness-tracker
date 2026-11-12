import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../shared/domain/training.dart';
import '../../shared/widgets/exercise_icon.dart';
import '../../shared/widgets/ui.dart';
import '../goals/goal_page.dart';
import '../history/entry_row.dart';
import '../logging/log_page.dart';
import '../progress/date_range_page.dart';
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
          message:
              'This hides the exercise and its history until you restore it.',
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

  Future<void> _delete(Exercise exercise) async {
    if (_busy || _confirming) return;
    _confirming = true;
    try {
      if (!await confirmExerciseDeletion(context, exercise) || !mounted) return;
      setState(() => _busy = true);
      await ref.read(repositoryProvider).deleteExercise(exercise.id);
      if (!mounted) return;
      announce(context, 'Exercise deleted.');
      if (ModalRoute.of(context)?.isCurrent == true) {
        await Navigator.maybePop(context);
      }
    } catch (error) {
      if (mounted) {
        announce(
          context,
          describeError(error, fallback: 'Couldn’t delete this exercise.'),
        );
      }
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
                  await openExerciseEditor(context, item: item);
                } else if (choice == 'delete') {
                  await _delete(exercise);
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
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    'Delete exercise',
                    style: TextStyle(color: context.colors.danger),
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
                  message: 'This exercise is no longer on this device.',
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ScreenHeading(
                    exercise.name,
                    leading: ExerciseIcon(exercise.name, size: 40),
                    top: 0,
                    subtitle:
                        '${exercise.measurement.label}${exercise.archived ? ' · Archived' : ''}',
                  ),
                  if (exercise.archived)
                    const Text(
                      'Restore this exercise to see its history again.',
                    )
                  else ...[
                    PerformanceView(
                      exercise: exercise,
                      range: selectionBounds(_range, today),
                      rangeAction: FilterButton(_range.preset.label, () async {
                        final selected = await selectRange(
                          context,
                          _range,
                          today,
                        );
                        if (mounted && selected != null) {
                          setState(() => _range = selected);
                        }
                      }),
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
                    SectionTitle('Recorded activity', key: _entryHeading),
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
                width: 1100,
                label: exercise.archived ? 'Restore exercise' : 'Add entry',
                busy: _busy,
                onPressed: exercise.archived
                    ? () => _archive(exercise)
                    : () => showLogSheet(
                        context,
                        request: LogRequest(exercise: exercise),
                      ),
              ),
            ),
    );
  }
}
