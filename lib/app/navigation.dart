import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../features/data_transfer/transfer_page.dart';
import '../features/exercises/exercise_detail.dart';
import '../features/exercises/exercise_library.dart';
import '../features/history/history_page.dart';
import '../features/logging/log_page.dart';
import '../features/overview/overview_page.dart';
import '../features/progress/progress_page.dart';
import '../features/settings/settings_page.dart';
import '../shared/widgets/ui.dart';
import 'providers.dart';
import 'theme.dart';

GoRouter createRouter() => GoRouter(
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => PrimaryShell(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const OverviewPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/progress',
              builder: (context, state) => const ProgressPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/history',
              builder: (context, state) => const HistoryPage(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsPage(),
    ),
    GoRoute(
      path: '/exercises',
      builder: (context, state) => const ExerciseLibrary(),
    ),
    GoRoute(
      path: '/exercise/:id',
      builder: (context, state) =>
          ExerciseDetail(id: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/log',
      builder: (context, state) => LogPage(request: state.extra as LogRequest?),
    ),
    GoRoute(
      path: '/transfer/:kind',
      builder: (context, state) => TransferPage(
        activity: state.pathParameters['kind'] == 'activity',
        recoveryFile: state.extra as String?,
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
                ),
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
                          onTap: () => context.push('/log'),
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
      child: Row(
        children: [
          for (final (i, label) in labels.indexed)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == selected,
                child: Material(
                  color: i == selected
                      ? context.colors.pill
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(100),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(100),
                    onTap: () => onSelect(i),
                    child: SizedBox(
                      height: 48,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              label,
                              maxLines: 1,
                              style: context.type.labelLarge?.copyWith(
                                color: i == selected
                                    ? context.colors.onPill
                                    : context.colors.ink,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
