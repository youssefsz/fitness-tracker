import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/database/tracker_repository.dart';
import '../../shared/domain/body_metrics.dart';
import '../../shared/domain/training.dart';
import '../../shared/widgets/exercise_icon.dart';
import '../../shared/widgets/ui.dart';
import 'exercise_order_sheet.dart';
import '../history/entry_row.dart';
import '../logging/log_page.dart';
import '../profile/profile_avatar.dart';
import '../progress/performance_chart.dart';
import '../update/android_update_host.dart';

enum _ExerciseListAction { reorder, library }

class OverviewPage extends ConsumerWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            final summaries = data.exercises
                .where((summary) => map.containsKey(summary.exerciseId))
                .toList();
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
                    action: PopupMenuButton<_ExerciseListAction>(
                      tooltip: 'Exercise options',
                      icon: const Icon(LucideIcons.ellipsis, size: 22),
                      onSelected: (choice) async {
                        switch (choice) {
                          case _ExerciseListAction.reorder:
                            await showExerciseOrderSheet(
                              context,
                              items: [
                                for (final summary in summaries)
                                  (
                                    exercise: map[summary.exerciseId]!,
                                    summary: summary,
                                  ),
                              ],
                              style: style,
                              customOrder:
                                  preferences
                                      ?.overviewExerciseOrder
                                      .isNotEmpty ??
                                  false,
                            );
                          case _ExerciseListAction.library:
                            if (context.mounted) context.push('/exercises');
                        }
                      },
                      itemBuilder: (_) => [
                        if (summaries.length > 1)
                          const PopupMenuItem(
                            value: _ExerciseListAction.reorder,
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(LucideIcons.arrowDownUp, size: 20),
                              title: Text('Reorder exercises'),
                            ),
                          ),
                        const PopupMenuItem(
                          value: _ExerciseListAction.library,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(LucideIcons.dumbbell, size: 20),
                            title: Text('Exercise library'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final summary in summaries)
                    _ExerciseSummary(
                      exercise: map[summary.exerciseId]!,
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
    final percent = summary.first == 0
        ? null
        : (change / summary.first * 100).round();
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
                      if (summary.count > 1 && (percent != null || change != 0))
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
