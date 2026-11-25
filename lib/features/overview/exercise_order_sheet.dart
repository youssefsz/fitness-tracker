import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/database/tracker_repository.dart' show OverviewExercise;
import '../../shared/domain/training.dart';
import '../../shared/widgets/exercise_icon.dart';
import '../../shared/widgets/ui.dart';

typedef ExerciseOrderItem = ({Exercise exercise, OverviewExercise summary});

Future<void> showExerciseOrderSheet(
  BuildContext context, {
  required List<ExerciseOrderItem> items,
  required DurationStyle style,
  required bool customOrder,
}) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  useSafeArea: true,
  isScrollControlled: true,
  constraints: BoxConstraints(
    maxWidth: 540,
    maxHeight: MediaQuery.sizeOf(context).height * .9,
  ),
  sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
      ? AnimationStyle.noAnimation
      : null,
  builder: (_) =>
      _ExerciseOrderSheet(items: items, style: style, customOrder: customOrder),
);

enum _Move { up, down, first, last }

class _ExerciseOrderSheet extends ConsumerStatefulWidget {
  const _ExerciseOrderSheet({
    required this.items,
    required this.style,
    required this.customOrder,
  });

  final List<ExerciseOrderItem> items;
  final DurationStyle style;
  final bool customOrder;

  @override
  ConsumerState<_ExerciseOrderSheet> createState() =>
      _ExerciseOrderSheetState();
}

class _ExerciseOrderSheetState extends ConsumerState<_ExerciseOrderSheet> {
  late final _initial = widget.items.map((item) => item.exercise.id).toList();
  late final _items = {for (final item in widget.items) item.exercise.id: item};
  late List<String> _order = List.of(_initial);
  late final _initialRecent = !widget.customOrder;
  late bool _recent = _initialRecent;
  bool _saving = false;
  String? _problem;
  ({String id, int pointer})? _press;

  void _beginPress(String id, int pointer) {
    if (_saving || _press != null) return;
    setState(() => _press = (id: id, pointer: pointer));
  }

  void _endPress([int? pointer]) {
    if (!mounted ||
        _press == null ||
        pointer != null && _press!.pointer != pointer) {
      return;
    }
    setState(() => _press = null);
  }

  bool get _changed =>
      _recent != _initialRecent || !listEquals(_order, _initial);

  void _move(int from, int to) {
    if (_saving || from == to || to < 0 || to >= _order.length) return;
    setState(() {
      final id = _order.removeAt(from);
      _order.insert(to, id);
      _recent = false;
      _problem = null;
    });
  }

  void _useRecent() => setState(() {
    _order = List.of(_initial)
      ..sort((a, b) {
        final byDate = _items[b]!.summary.latestDay.compareTo(
          _items[a]!.summary.latestDay,
        );
        return byDate != 0 ? byDate : a.compareTo(b);
      });
    _recent = true;
    _problem = null;
  });

  Future<void> _save() async {
    if (_saving) return;
    if (!_changed) {
      _saving = true;
      Navigator.pop(context);
      return;
    }
    setState(() {
      _saving = true;
      _press = null;
      _problem = null;
    });
    try {
      final repo = ref.read(repositoryProvider);
      if (_recent) {
        await repo.resetOverviewExerciseOrder();
      } else {
        await repo.saveOverviewExerciseOrder(List.of(_order));
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _problem = describeError(error);
        });
      }
    }
  }

  Widget _exerciseRow(
    BuildContext context,
    int index, {
    bool pickedUp = false,
  }) {
    final item = _items[_order[index]]!;
    final up = index > 0 && !_saving;
    final down = index < _order.length - 1 && !_saving;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm,
        vertical: Space.md,
      ),
      child: Row(
        children: [
          ExerciseIcon(item.exercise.name),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.exercise.name, style: context.type.titleMedium),
                const SizedBox(height: Space.xs),
                Text(
                  'Latest ${measure(item.summary.latest, item.exercise.measurement, widget.style)}',
                  style: context.type.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.sm),
          TooltipTheme(
            key: ValueKey('reorder-handle-${item.exercise.id}'),
            data: TooltipTheme.of(context)
                .copyWith(triggerMode: TooltipTriggerMode.manual),
            child: PopupMenuButton<_Move>(
              tooltip: 'Reorder ${item.exercise.name}',
              enabled: !_saving,
              icon: Icon(
                Icons.drag_handle,
                color: pickedUp ? context.colors.green : context.colors.muted,
              ),
              onSelected: (move) => _move(index, switch (move) {
                _Move.up => index - 1,
                _Move.down => index + 1,
                _Move.first => 0,
                _Move.last => _order.length - 1,
              }),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _Move.up,
                  enabled: up,
                  child: Row(
                    children: [
                      Icon(LucideIcons.arrowUp, size: 18),
                      const SizedBox(width: Space.sm),
                      const Flexible(child: Text('Move up')),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: _Move.down,
                  enabled: down,
                  child: Row(
                    children: [
                      Icon(LucideIcons.arrowDown, size: 18),
                      const SizedBox(width: Space.sm),
                      const Flexible(child: Text('Move down')),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: _Move.first,
                  enabled: up,
                  child: Row(
                    children: [
                      Icon(LucideIcons.arrowUpToLine, size: 18),
                      const SizedBox(width: Space.sm),
                      const Flexible(child: Text('Move to top')),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: _Move.last,
                  enabled: down,
                  child: Row(
                    children: [
                      Icon(LucideIcons.arrowDownToLine, size: 18),
                      const SizedBox(width: Space.sm),
                      const Flexible(child: Text('Move to bottom')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _orderControl({required bool recent}) => TextButton(
    style: TextButton.styleFrom(
      alignment: AlignmentDirectional.centerStart,
      minimumSize: const Size(0, Space.target),
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 12),
      disabledForegroundColor: context.colors.muted,
    ),
    onPressed: recent || _saving ? null : _useRecent,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(recent ? LucideIcons.check : LucideIcons.rotateCcw, size: 18),
        const SizedBox(width: Space.sm),
        Flexible(
          child: Text(recent ? 'Recent activity order' : 'Use recent order'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.lg, Space.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: Space.md),
                Flexible(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(80, Space.target),
                    ),
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Saving…' : 'Done'),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: NotificationListener<ScrollStartNotification>(
              onNotification: (_) {
                _endPress();
                return false;
              },
              child: CustomScrollView(
                key: const ValueKey('exercise-order-list'),
                shrinkWrap: true,
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            Space.lg,
                            0,
                            Space.lg,
                            Space.md,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Semantics(
                                header: true,
                                child: Text(
                                  'Reorder exercises',
                                  style: context.type.titleLarge,
                                ),
                              ),
                              const SizedBox(height: Space.sm),
                              Text(
                                'Hold any row to drag. Tap a handle for move options.',
                                style: context.type.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: Space.lg),
                          child: Divider(),
                        ),
                      ],
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                    sliver: SliverReorderableList(
                      itemCount: _order.length,
                      onReorderItem: _move,
                      onReorderStart: (_) {
                        _endPress();
                        ref.read(actionsProvider).startDrag();
                      },
                      proxyDecorator: (_, index, animation) => AnimatedBuilder(
                        animation: animation,
                        child: _exerciseRow(context, index, pickedUp: true),
                        builder: (context, child) => Material(
                          key: const ValueKey('exercise-order-drag-proxy'),
                          color: Color.alphaBlend(
                            context.colors.green.withValues(alpha: .1),
                            context.colors.surface,
                          ),
                          surfaceTintColor: Colors.transparent,
                          elevation: MediaQuery.disableAnimationsOf(context)
                              ? 0
                              : 3 * Curves.easeOut.transform(animation.value),
                          borderRadius: BorderRadius.circular(Space.radius),
                          clipBehavior: Clip.antiAlias,
                          child: child,
                        ),
                      ),
                      itemBuilder: (context, index) {
                        final item = _items[_order[index]]!;
                        final up = index > 0 && !_saving;
                        final down = index < _order.length - 1 && !_saving;
                        return ReorderableDelayedDragStartListener(
                          key: ValueKey(item.exercise.id),
                          index: index,
                          enabled: !_saving,
                          child: Semantics(
                            customSemanticsActions: {
                              if (up)
                                CustomSemanticsAction(label: 'Move up'): () =>
                                    _move(index, index - 1),
                              if (down)
                                CustomSemanticsAction(label: 'Move down'): () =>
                                    _move(index, index + 1),
                            },
                            child: ColoredBox(
                              color: Colors.transparent,
                              child: Column(
                                children: [
                                  Listener(
                                    behavior: HitTestBehavior.opaque,
                                    onPointerDown: (event) => _beginPress(
                                      item.exercise.id,
                                      event.pointer,
                                    ),
                                    onPointerUp: (event) =>
                                        _endPress(event.pointer),
                                    onPointerCancel: (event) =>
                                        _endPress(event.pointer),
                                    child: DecoratedBox(
                                      key: ValueKey(
                                        'reorder-press-${item.exercise.id}',
                                      ),
                                      decoration: BoxDecoration(
                                        color: _press?.id == item.exercise.id
                                            ? Color.alphaBlend(
                                                context.colors.ink.withValues(
                                                  alpha: .06,
                                                ),
                                                context.colors.surface,
                                              )
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(
                                          Space.radius,
                                        ),
                                      ),
                                      child: _exerciseRow(context, index),
                                    ),
                                  ),
                                  const Divider(height: 1),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: Space.lg),
            child: Divider(height: 1),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.md,
              Space.sm,
              Space.lg,
              Space.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Size both labels so switching states cannot resize the sheet,
                // including when larger text makes either label wrap.
                IndexedStack(
                  key: const ValueKey('exercise-order-footer'),
                  index: _recent ? 0 : 1,
                  alignment: AlignmentDirectional.centerStart,
                  children: [
                    _orderControl(recent: true),
                    _orderControl(recent: false),
                  ],
                ),
                FormProblem(_problem),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
