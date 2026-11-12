import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/database/tracker_repository.dart';
import '../../shared/domain/training.dart';
import '../../shared/widgets/draft_sheet.dart';
import '../../shared/widgets/exercise_icon.dart';
import '../../shared/widgets/ui.dart';

Future<Exercise?> openExerciseEditor(
  BuildContext context, {
  CatalogItem? item,
  bool hasGoal = false,
}) => Navigator.of(context).push<Exercise>(
  item == null
      ? DraftSheetRoute<Exercise>(
          context: context,
          builder: (_) => const ExerciseEditor(),
        )
      : platformPageRoute<Exercise>(
          context,
          (_) => ExerciseEditor(item: item, hasGoal: hasGoal),
        ),
);

class ExerciseLibrary extends ConsumerStatefulWidget {
  const ExerciseLibrary({super.key});

  @override
  ConsumerState<ExerciseLibrary> createState() => _ExerciseLibraryState();
}

class _ExerciseLibraryState extends ConsumerState<ExerciseLibrary> {
  var _search = '';
  final _busy = <String>{};

  Future<void> _edit(CatalogItem item) async {
    try {
      final goal = await ref.read(goalProvider(item.exercise.id).future);
      if (!mounted) return;
      await openExerciseEditor(context, item: item, hasGoal: goal != null);
    } catch (error) {
      if (mounted) announce(context, describeError(error));
    }
  }

  Future<void> _archive(Exercise exercise) async {
    if (_busy.contains(exercise.id)) return;
    setState(() => _busy.add(exercise.id));
    try {
      if (!exercise.archived) {
        final confirmed = await confirmAction(
          context,
          title: 'Archive ${exercise.name}?',
          message: 'It will disappear from logging suggestions. Your records and goal stay available.',
          label: 'Archive',
        );
        if (!mounted || !confirmed) return;
      }
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
      if (mounted) setState(() => _busy.remove(exercise.id));
    }
  }

  Widget _row(CatalogItem item) {
    final x = item.exercise;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: RowLink(
                title: x.name,
                leading: ExerciseIcon(x.name),
                subtitle:
                    '${x.measurement.label} · ${item.count == 0 ? 'No entries' : '${item.count} ${item.count == 1 ? 'set' : 'sets'}'}',
                onTap: () => context.push('/exercise/${x.id}'),
                separator: false,
              ),
            ),
            if (x.archived)
              QuietButton(
                'Restore',
                _busy.contains(x.id) ? null : () => _archive(x),
              )
            else ...[
              QuietButton(
                'Edit',
                _busy.contains(x.id) ? null : () => _edit(item),
              ),
              PopupMenuButton<String>(
                tooltip: 'Manage ${x.name}',
                enabled: !_busy.contains(x.id),
                icon: const Icon(LucideIcons.ellipsis, size: 20),
                onSelected: (_) => _archive(x),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'archive', child: Text('Archive')),
                ],
              ),
            ],
          ],
        ),
        const Divider(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: secondaryBar(context),
    body: ScreenScroll(
      children: [
        AsyncPanel(
          ref.watch(catalogProvider),
          retry: () => ref.invalidate(catalogProvider),
          builder: (items) {
            final active = items.where((i) => !i.exercise.archived).length;
            final matches = items
                .where((i) => normalizeName(i.exercise.name).contains(_search))
                .toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ScreenHeading(
                  'Exercises',
                  top: 0,
                  subtitle:
                      '$active active · ${items.length - active} archived',
                  action: QuietButton(
                    'New',
                    () => openExerciseEditor(context),
                    icon: LucideIcons.plus,
                  ),
                ),
                SearchInput(
                  hint: 'Search exercises',
                  onChanged: (input) =>
                      setState(() => _search = normalizeName(input)),
                ),
                const SizedBox(height: 12),
                if (matches.isEmpty)
                  EmptyBlock(
                    title: items.isEmpty
                        ? 'Build your exercise list'
                        : 'No matching exercises',
                    message: items.isEmpty
                        ? 'Create an exercise to start tracking its sets.'
                        : 'Try another exercise name.',
                  ),
                for (final item in matches.where((i) => !i.exercise.archived))
                  _row(item),
                if (matches.any((i) => i.exercise.archived)) ...[
                  const SizedBox(height: 24),
                  const SectionTitle('Archived'),
                  const SizedBox(height: 5),
                  for (final item in matches.where((i) => i.exercise.archived))
                    _row(item),
                  const SizedBox(height: 12),
                  Text(
                    'Archived exercises keep their recorded history.',
                    style: context.type.bodySmall,
                  ),
                ],
              ],
            );
          },
        ),
      ],
    ),
  );
}

typedef ExerciseEditorLayout = Widget Function({
  required bool Function() dirty,
  required bool Function() busy,
  required Widget child,
  required Widget footer,
});

class ExerciseEditor extends ConsumerStatefulWidget {
  const ExerciseEditor({this.item, this.hasGoal = false, super.key})
    : onCreated = null,
      layout = null;

  const ExerciseEditor.inSheet({
    required this.onCreated,
    required this.layout,
    super.key,
  }) : item = null,
       hasGoal = false;

  final CatalogItem? item;
  final bool hasGoal;
  final ValueChanged<Exercise>? onCreated;
  final ExerciseEditorLayout? layout;

  @override
  ConsumerState<ExerciseEditor> createState() => _ExerciseEditorState();
}

class _ExerciseEditorState extends ConsumerState<ExerciseEditor> {
  Exercise? get _original => widget.item?.exercise;
  late final _name = TextEditingController(text: _original?.name);
  late var _measurement = _original?.measurement ?? Measurement.repetitions;
  bool _busy = false, _confirming = false;
  String? _error;

  bool get _dirty =>
      _name.text.trim() != (_original?.name ?? '') ||
      _measurement != (_original?.measurement ?? Measurement.repetitions);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final name = _name.text.trim();
    if (exerciseNameError(name) case final error?) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(repositoryProvider);
      if (_original case final x?) {
        await repo.editExercise(x.id, name, _measurement);
        if (mounted) {
          announce(context, 'Exercise updated.');
          Navigator.pop(context);
        }
      } else {
        final exercise = await repo.createExercise(name, _measurement);
        if (!mounted) return;
        if (widget.onCreated case final onCreated?) {
          onCreated(exercise);
        } else if (ModalRoute.of(context)
            case final DraftSheetRoute<Exercise> route) {
          route.finish(exercise);
        } else {
          Navigator.pop(context, exercise);
        }
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = describeError(
            error,
            fallback: 'Couldn’t save this exercise. Try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _closeSheet(DraftSheetRoute<Exercise> route) async {
    if (_busy || _confirming) return;
    FocusScope.of(context).unfocus();
    if (_dirty) {
      _confirming = true;
      try {
        final discard = await confirmAction(
          context,
          title: 'Discard changes?',
          message: 'Your unsaved exercise will be lost.',
          label: 'Discard',
          destructive: true,
        );
        if (!mounted || !discard) return;
      } finally {
        _confirming = false;
      }
    }
    route.finish();
  }

  @override
  Widget build(BuildContext context) {
    final locked = (widget.item?.count ?? 0) > 0 || widget.hasGoal;
    final title = _original == null ? 'New exercise' : 'Edit exercise';
    final footer = ActionFooter(
      label: _original == null ? 'Create exercise' : 'Save exercise',
      busy: _busy,
      onPressed: _save,
    );
    final children = <Widget>[
      const SizedBox(height: 10),
      const SectionTitle('Exercise name'),
      const SizedBox(height: 10),
      TextField(
        controller: _name,
        enabled: !_busy,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        decoration: lineInput(context, label: 'Name', error: _error),
        onChanged: (_) => setState(() => _error = null),
      ),
      const SizedBox(height: 26),
      const SectionTitle('Measure in'),
      const SizedBox(height: 6),
      RadioGroup<Measurement>(
        groupValue: _measurement,
        onChanged: (value) {
          if (value == null || locked || _busy) return;
          ref.read(actionsProvider).select();
          setState(() => _measurement = value);
        },
        child: Column(
          children: [
            for (final m in Measurement.values) ...[
              RadioListTile<Measurement>(
                value: m,
                enabled: !locked && !_busy,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.trailing,
                title: Text(m.label),
                subtitle: Text(
                  m == Measurement.repetitions
                      ? 'Count each rep'
                      : 'Minutes and seconds',
                ),
              ),
              const Divider(),
            ],
          ],
        ),
      ),
      const SizedBox(height: Space.md),
      Text(
        locked
            ? 'Measurement is locked while this exercise has recorded sets or a goal.'
            : 'Choose the measurement you want to track.',
        style: context.type.bodySmall,
      ),
      if (!locked) ...[
        const SizedBox(height: Space.md),
        Wrap(
          spacing: Space.md,
          children: [
            Text('Example entry', style: context.type.bodySmall),
            Text(
              _measurement == Measurement.repetitions
                  ? '12 reps'
                  : '1 min 30 sec',
              style: context.type.labelMedium,
            ),
          ],
        ),
      ],
    ];
    if (widget.layout case final layout?) {
      return layout(
        dirty: () => _dirty,
        busy: () => _busy,
        child: ScreenScroll(children: children),
        footer: footer,
      );
    }
    if (ModalRoute.of(context) case final DraftSheetRoute<Exercise> route) {
      route.hasProtectedDraft = () => _dirty || _busy || _confirming;
      route.onDismissBlocked = () => _closeSheet(route);
      return PopScope<Exercise>(
        canPop: !_dirty && !_busy,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _closeSheet(route);
        },
        child: SheetLayout(
          title: title,
          closeLabel: 'Cancel exercise',
          close: _busy ? null : () => _closeSheet(route),
          footer: footer,
          child: ScreenScroll(children: children),
        ),
      );
    }
    return ProtectDraft<Exercise>(
      dirty: _dirty,
      busy: _busy,
      child: FormLayout(title: title, footer: footer, children: children),
    );
  }
}
