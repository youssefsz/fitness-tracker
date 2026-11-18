import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/database/tracker_repository.dart';
import '../../shared/domain/body_metrics.dart';
import '../../shared/domain/training.dart';
import '../../shared/widgets/exercise_icon.dart';
import '../../shared/widgets/ui.dart';
import '../history/entry_row.dart';
import '../logging/log_page.dart';
import '../profile/profile_avatar.dart';
import '../progress/performance_chart.dart';
import '../update/android_update_host.dart';

class OverviewPage extends ConsumerStatefulWidget {
  const OverviewPage({super.key});

  @override
  ConsumerState<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends ConsumerState<OverviewPage> {
  bool _reordering = false;
  bool _savingOrder = false;
  List<String> _draftOrder = [];

  void _startReordering(List<String> ids) {
    setState(() {
      _reordering = true;
      _draftOrder = List.of(ids);
    });
  }

  void _cancelReordering() => setState(() {
    _reordering = false;
    _draftOrder = [];
  });

  List<String> _currentDraft(List<String> ids) => [
    ..._draftOrder.where(ids.contains),
    ...ids.where((id) => !_draftOrder.contains(id)),
  ];

  void _move(int from, int to, List<String> ids) {
    final order = _reordering ? _currentDraft(ids) : ids;
    if (to < 0 || to >= order.length || from == to) return;
    setState(() {
      final id = order.removeAt(from);
      order.insert(to, id);
      _draftOrder = order;
    });
  }

  Future<void> _saveOrder(List<String> ids) async {
    setState(() => _savingOrder = true);
    try {
      await ref
          .read(repositoryProvider)
          .saveOverviewExerciseOrder(_currentDraft(ids));
      if (mounted) {
        setState(() {
          _savingOrder = false;
          _reordering = false;
          _draftOrder = [];
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _savingOrder = false);
        announce(context, describeError(error));
      }
    }
  }

  Future<void> _resetOrder() async {
    setState(() => _savingOrder = true);
    try {
      await ref.read(repositoryProvider).resetOverviewExerciseOrder();
      if (mounted) {
        setState(() {
          _savingOrder = false;
          _reordering = false;
          _draftOrder = [];
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _savingOrder = false);
        announce(context, describeError(error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    final value = ref.watch(overviewProvider);
    final overview = value.value;
    final exerciseCount = overview?.exercises.length ?? 0;
    final style = ref.watch(durationProvider);
    final preferences = ref.watch(preferencesProvider).value;
    final content = value.hasValue && value.requireValue.exercises.isNotEmpty
        ? catalog.whenData((items) => (value.requireValue, items))
        : value.whenData((data) => (data, const <CatalogItem>[]));
    return ScreenScroll(
      primary: true,
      width: 1100,
      scrollKey: const PageStorageKey('overview'),
      children: [
        ScreenHeading(
          'Overview',
          subtitleLoading: !value.hasValue && !value.hasError,
          fadeSubtitle: false,
          subtitle: exerciseCount == 0
              ? null
              : '$exerciseCount ${exerciseCount == 1 ? 'exercise' : 'exercises'} · '
                    'Since ${fullDay(overview!.firstDay!)}',
          action: const _ProfileButton(),
        ),
        const AndroidUpdateRow(),
        AsyncPanel(
          content,
          loadingLabel: 'Loading overview',
          fadeContent: false,
          loading: ResponsiveSplit(
            main: _OverviewSectionSkeleton(
              headingWidth: 117,
              rows: const SkeletonRows(rowHeight: 97),
            ),
            side: _OverviewSectionSkeleton(
              headingWidth: 128,
              rows: const SkeletonRows(count: 2, rowHeight: 78),
            ),
          ),
          retry: () {
            if (value.hasError) ref.invalidate(overviewProvider);
            if (catalog.hasError) ref.invalidate(catalogProvider);
          },
          builder: (content) {
            final (data, items) = content;
            if (data.exercises.isEmpty) {
              return _FirstResult(
                hasExercises: catalog.value?.isNotEmpty ?? false,
              );
            }
            final map = {
              for (final row in items)
                if (!row.exercise.archived) row.exercise.id: row.exercise,
            };
            final storedOrder = preferences?.overviewExerciseOrder ?? const [];
            final storedIndex = {
              for (var i = 0; i < storedOrder.length; i++) storedOrder[i]: i,
            };
            final summaries = data.exercises
                .where((summary) => map.containsKey(summary.exerciseId))
                .toList();
            if (storedIndex.isNotEmpty) {
              summaries.sort((a, b) {
                final ai = storedIndex[a.exerciseId] ?? storedOrder.length;
                final bi = storedIndex[b.exerciseId] ?? storedOrder.length;
                if (ai != bi) return ai.compareTo(bi);
                final byDate = b.latestDay.compareTo(a.latestDay);
                return byDate != 0
                    ? byDate
                    : a.exerciseId.compareTo(b.exerciseId);
              });
            }
            final displayedSummaries = _reordering
                ? _currentDraft(
                        summaries.map((summary) => summary.exerciseId).toList(),
                      )
                      .map(
                        (id) => summaries.firstWhere(
                          (summary) => summary.exerciseId == id,
                        ),
                      )
                      .toList()
                : summaries;
            final ids = summaries.map((summary) => summary.exerciseId).toList();
            final recentByDay = <CalendarDay, List<Entry>>{};
            for (final entry in data.recent) {
              if (map.containsKey(entry.exerciseId)) {
                (recentByDay[entry.day] ??= []).add(entry);
              }
            }
            return ResponsiveSplit(
              main: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionTitle(
                    'Your exercises',
                    action: _reordering
                        ? Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 4,
                            children: [
                              QuietButton(
                                'Cancel',
                                _savingOrder ? null : _cancelReordering,
                              ),
                              TextButton(
                                onPressed: _savingOrder
                                    ? null
                                    : () => _saveOrder(ids),
                                child: const Text('Done'),
                              ),
                            ],
                          )
                        : Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 4,
                            children: [
                              if (storedIndex.isNotEmpty)
                                QuietButton('Reset to recent', _resetOrder),
                              if (summaries.length > 1)
                                QuietButton(
                                  'Reorder',
                                  () => _startReordering(ids),
                                ),
                              QuietButton(
                                'Manage',
                                () => context.push('/exercises'),
                              ),
                            ],
                          ),
                  ),
                  if (_reordering)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.xs),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Drag the handle to change the order.',
                              style: context.type.bodySmall?.copyWith(
                                color: context.colors.muted,
                              ),
                            ),
                          ),
                          if (storedIndex.isNotEmpty)
                            QuietButton('Reset to recent', _resetOrder),
                        ],
                      ),
                    ),
                  if (_reordering)
                    ReorderableListView(
                      primary: false,
                      shrinkWrap: true,
                      buildDefaultDragHandles: false,
                      onReorderItem: (oldIndex, newIndex) =>
                          _move(oldIndex, newIndex, ids),
                      children: [
                        for (
                          var index = 0;
                          index < displayedSummaries.length;
                          index++
                        )
                          _ExerciseSummary(
                            key: ValueKey(displayedSummaries[index].exerciseId),
                            exercise:
                                map[displayedSummaries[index].exerciseId]!,
                            summary: displayedSummaries[index],
                            style: style,
                            reordering: true,
                            index: index,
                            onMoveUp: index == 0
                                ? null
                                : () => _move(index, index - 1, ids),
                            onMoveDown: index == displayedSummaries.length - 1
                                ? null
                                : () => _move(index, index + 1, ids),
                          ),
                      ],
                    ),
                  if (!_reordering)
                    for (final summary in displayedSummaries)
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
                  for (final group in recentByDay.entries) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: Space.sm),
                      child: Text(
                        fullDay(group.key),
                        style: context.type.bodySmall,
                      ),
                    ),
                    for (final entry in group.value)
                      EntryRow(
                        key: ValueKey(entry.id),
                        entry: entry,
                        exercise: map[entry.exerciseId]!,
                        compact: true,
                      ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ProfileButton extends ConsumerWidget {
  const _ProfileButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    final colors = context.colors;
    return IconButton(
      tooltip: 'Profile',
      onPressed: () => context.push('/profile'),
      style: IconButton.styleFrom(
        backgroundColor: colors.input,
        foregroundColor: colors.ink,
        side: BorderSide(color: colors.border),
        shape: const CircleBorder(),
        padding: EdgeInsets.zero,
        fixedSize: const Size.square(Space.target),
      ),
      icon: ProfileAvatar(
        size: 38,
        photo: profile?.photo,
        preset: profile?.avatarPreset ?? AvatarPreset.anonymous,
        fallback: Image.asset(
          'assets/avatars/anonymous.webp',
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _OverviewSectionSkeleton extends StatelessWidget {
  const _OverviewSectionSkeleton({
    required this.headingWidth,
    required this.rows,
  });

  final double headingWidth;
  final SkeletonRows rows;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        height: Space.target,
        child: Center(
          widthFactor: 1,
          child: SkeletonText(
            width: headingWidth,
            style: context.type.titleLarge,
          ),
        ),
      ),
      rows,
    ],
  );
}

class _FirstResult extends StatelessWidget {
  const _FirstResult({required this.hasExercises});

  final bool hasExercises;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 445),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: Space.md),
          const EmptyStateIllustration(
            'assets/brand/first-result.webp',
            maxWidth: 360,
            aspectRatio: 1080 / 455,
          ),
          EmptyBlock(
            title: 'Start with one result.',
            message:
                'Log a set to see your latest result and track how it changes.',
            action: 'Log your first result',
            onAction: () => showLogSheet(context),
            secondary: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                QuietButton(
                  'Import a backup',
                  () => context.push('/transfer/backup'),
                ),
                if (hasExercises)
                  QuietButton(
                    'Manage exercises',
                    () => context.push('/exercises'),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _ExerciseSummary extends StatelessWidget {
  const _ExerciseSummary({
    super.key,
    required this.exercise,
    required this.summary,
    required this.style,
    this.reordering = false,
    this.index = 0,
    this.onMoveUp,
    this.onMoveDown,
  });
  final Exercise exercise;
  final OverviewExercise summary;
  final DurationStyle style;
  final bool reordering;
  final int index;
  final VoidCallback? onMoveUp, onMoveDown;

  @override
  Widget build(BuildContext context) {
    final measurement = exercise.measurement;
    final change = summary.latest - summary.first;
    final percent = summary.first == 0
        ? null
        : (change / summary.first * 100).round();
    final actions = <CustomSemanticsAction, VoidCallback>{};
    if (onMoveUp case final moveUp?) {
      actions[CustomSemanticsAction(label: 'Move up')] = moveUp;
    }
    if (onMoveDown case final moveDown?) {
      actions[CustomSemanticsAction(label: 'Move down')] = moveDown;
    }
    return Semantics(
      customSemanticsActions: reordering ? actions : null,
      child: Column(
        children: [
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: reordering
                  ? null
                  : () => context.push('/exercise/${exercise.id}'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: LayoutBuilder(
                  builder: (context, size) {
                    final identity = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            ExerciseIcon(exercise.name),
                            const SizedBox(width: Space.sm),
                            Flexible(
                              child: Text(
                                exercise.name,
                                style: context.type.titleMedium,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Best ${measure(summary.best, measurement, style)} · First ${measure(summary.first, measurement, style)}',
                          style: context.type.bodySmall,
                        ),
                        if (summary.count > 1 &&
                            (percent != null || change != 0))
                          Text(
                            percent == null
                                ? '${changeText(change, measurement, style)} since first'
                                : '${signed(percent)}% since first',
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
                                  'Latest result: ${measure(summary.latest, measurement, style, accessible: true)}',
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
                        children: [
                          if (reordering)
                            Row(
                              children: [
                                _ExerciseDragHandle(
                                  exercise: exercise,
                                  index: index,
                                ),
                                Expanded(child: identity),
                              ],
                            )
                          else
                            identity,
                          const SizedBox(height: 8),
                          latest,
                        ],
                      );
                    }
                    final row = Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (reordering)
                          _ExerciseDragHandle(exercise: exercise, index: index),
                        Expanded(flex: 5, child: identity),
                        const SizedBox(width: 12),
                        Expanded(flex: 4, child: latest),
                      ],
                    );
                    return row;
                  },
                ),
              ),
            ),
          ),
          const Divider(),
        ],
      ),
    );
  }
}

class _ExerciseDragHandle extends StatelessWidget {
  const _ExerciseDragHandle({required this.exercise, required this.index});

  final Exercise exercise;
  final int index;

  @override
  Widget build(BuildContext context) => Semantics(
    key: ValueKey('reorder-handle-${exercise.id}'),
    container: true,
    label: 'Reorder ${exercise.name}',
    hint: 'Hold and drag to change its order.',
    child: ReorderableDelayedDragStartListener(
      index: index,
      child: const SizedBox.square(
        dimension: Space.target,
        child: Center(child: Icon(Icons.drag_indicator)),
      ),
    ),
  );
}
