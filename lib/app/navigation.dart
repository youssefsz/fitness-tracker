import 'package:flutter/cupertino.dart' show CupertinoPage;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../features/data_transfer/transfer_page.dart';
import '../features/data_transfer/your_data_page.dart';
import '../features/exercises/exercise_detail.dart';
import '../features/exercises/exercise_library.dart';
import '../features/history/history_page.dart';
import '../features/logging/log_page.dart';
import '../features/overview/overview_page.dart';
import '../features/profile/edit_profile_page.dart';
import '../features/profile/profile_page.dart';
import '../features/profile/weight_page.dart';
import '../features/progress/progress_page.dart';
import '../shared/domain/training.dart';
import '../shared/widgets/ui.dart';
import 'providers.dart';
import 'theme.dart';

GoRouter createRouter() => GoRouter(
  routes: [
    StatefulShellRoute.indexedStack(
      pageBuilder: (context, state, shell) =>
          _platformPage(context, state, PrimaryShell(shell: shell)),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              pageBuilder: (context, state) => NoTransitionPage<void>(
                key: state.pageKey,
                child: const OverviewPage(),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/progress',
              pageBuilder: (context, state) => NoTransitionPage<void>(
                key: state.pageKey,
                child: const ProgressPage(),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/history',
              pageBuilder: (context, state) => NoTransitionPage<void>(
                key: state.pageKey,
                child: const HistoryPage(),
              ),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/profile',
      pageBuilder: (context, state) =>
          _platformPage(context, state, const ProfilePage()),
      routes: [
        GoRoute(
          path: 'edit',
          pageBuilder: (context, state) =>
              _platformPage(context, state, const EditProfilePage()),
        ),
        GoRoute(
          path: 'weight',
          pageBuilder: (context, state) =>
              _platformPage(context, state, const WeightHistoryPage()),
        ),
        GoRoute(
          path: 'weigh-in',
          pageBuilder: (context, state) => _platformPage(
            context,
            state,
            WeightFormPage(original: state.extra as WeighIn?),
          ),
        ),
        GoRoute(
          path: 'data',
          pageBuilder: (context, state) =>
              _platformPage(context, state, const YourDataPage()),
        ),
      ],
    ),
    GoRoute(path: '/settings', redirect: (_, _) => '/profile'),
    GoRoute(
      path: '/exercises',
      pageBuilder: (context, state) =>
          _platformPage(context, state, const ExerciseLibrary()),
    ),
    GoRoute(
      path: '/exercise/:id',
      pageBuilder: (context, state) => _platformPage(
        context,
        state,
        ExerciseDetail(id: state.pathParameters['id']!),
      ),
    ),
    GoRoute(
      path: '/log',
      redirect: (_, state) =>
          (state.extra as LogRequest?)?.entry == null ? '/' : null,
      pageBuilder: (context, state) => _platformPage(
        context,
        state,
        LogPage(request: state.extra as LogRequest),
      ),
    ),
    GoRoute(
      path: '/transfer/:kind',
      pageBuilder: (context, state) => _platformPage(
        context,
        state,
        TransferPage(
          activity: state.pathParameters['kind'] == 'activity',
          recoveryFile: state.extra as String?,
        ),
      ),
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: EmptyBlock(
          title: 'Page unavailable',
          message: 'Open Overview to continue.',
          action: 'Go to Overview',
          onAction: () => context.go('/'),
        ),
      ),
    ),
  ),
);

Page<void> _platformPage(
  BuildContext context,
  GoRouterState state,
  Widget child,
) => Theme.of(context).platform == TargetPlatform.iOS
    ? CupertinoPage<void>(key: state.pageKey, child: child)
    : MaterialPage<void>(key: state.pageKey, child: child);

class PrimaryShell extends ConsumerWidget {
  const PrimaryShell({required this.shell, super.key});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    extendBody: true,
    body: shell,
    bottomNavigationBar: MediaQuery.viewInsetsOf(context).bottom > 0
        ? null
        : SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 12),
            child: Center(
              heightFactor: 1,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: MediaQuery.sizeOf(context).width < 350 ? 16 : 20,
                ).copyWith(bottom: Space.sm),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 438),
                  child: Row(
                    children: [
                      Expanded(
                        child: _Capsule(
                          selected: shell.currentIndex,
                          onSelect: (index) {
                            if (index != shell.currentIndex) {
                              ref.read(actionsProvider).select();
                              shell.goBranch(index);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Material(
                        color: context.colors.add,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => showLogSheet(context),
                          child: const SizedBox.square(
                            dimension: 56,
                            child: Center(
                              child: Icon(
                                LucideIcons.plus,
                                size: 27,
                                color: Color(0xff19271f),
                              ),
                            ),
                          ),
                        ),
                      ).withLabel('Add entry'),
                    ],
                  ),
                ),
              ),
            ),
          ),
  );
}

extension on Widget {
  Widget withLabel(String label) => Semantics(
    button: true,
    label: label,
    child: Tooltip(message: label, excludeFromSemantics: true, child: this),
  );
}

class _Capsule extends StatelessWidget {
  const _Capsule({required this.selected, required this.onSelect});
  final int selected;
  final ValueChanged<int> onSelect;
  static const labels = ['Overview', 'Progress', 'History'];
  static const shape = StadiumBorder();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(100),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: context.dark ? .28 : .09),
          offset: const Offset(0, 2),
          blurRadius: 10,
        ),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: SizedBox(
        height: Space.target,
        child: LayoutBuilder(
          builder: (context, limits) {
            final tabWidth = limits.maxWidth / labels.length;
            final rtl = Directionality.of(context) == TextDirection.rtl;
            final selectedPosition =
                (rtl ? labels.length - 1 - selected : selected).toDouble();
            return TweenAnimationBuilder<double>(
              tween: Tween(begin: selectedPosition, end: selectedPosition),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 190),
              curve: Curves.easeOutCubic,
              child: Material(
                type: MaterialType.transparency,
                child: Row(
                  children: [
                    for (final (i, label) in labels.indexed)
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: i == selected,
                          child: InkWell(
                            customBorder: shape,
                            onTap: () => onSelect(i),
                            child: _TabLabel(
                              Text(
                                label,
                                maxLines: 1,
                                style: context.type.labelLarge,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              builder: (context, position, tabs) {
                final bounds = Rect.fromLTWH(
                  position * tabWidth,
                  0,
                  tabWidth,
                  Space.target,
                );
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fromRect(
                      rect: bounds,
                      child: DecoratedBox(
                        key: const ValueKey('primary-tab-indicator'),
                        decoration: ShapeDecoration(
                          color: context.colors.pill,
                          shape: shape,
                        ),
                      ),
                    ),
                    tabs!,
                    // Draw the light lettering only where the pill is beneath it.
                    IgnorePointer(
                      child: ExcludeSemantics(
                        child: ClipPath(
                          clipper: _PillClipper(bounds),
                          child: Row(
                            children: [
                              for (final label in labels)
                                Expanded(
                                  child: _TabLabel(
                                    RichText(
                                      maxLines: 1,
                                      textScaler: MediaQuery.textScalerOf(
                                        context,
                                      ),
                                      text: TextSpan(
                                        text: label,
                                        style: context.type.labelLarge
                                            ?.copyWith(
                                              color: context.colors.onPill,
                                            ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    ),
  );
}

class _TabLabel extends StatelessWidget {
  const _TabLabel(this.child);
  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: FittedBox(fit: BoxFit.scaleDown, child: child),
    ),
  );
}

class _PillClipper extends CustomClipper<Path> {
  const _PillClipper(this.bounds);
  final Rect bounds;

  @override
  Path getClip(Size size) => _Capsule.shape.getOuterPath(bounds);

  @override
  bool shouldReclip(_PillClipper oldClipper) => bounds != oldClipper.bounds;
}
