import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/database/tracker_repository.dart';
import '../../shared/domain/training.dart';
import '../../shared/widgets/ui.dart';

Future<Exercise?> openExerciseEditor(
  BuildContext context, {
  CatalogItem? item,
  bool hasGoal = false,
}) => Navigator.of(context).push<Exercise>(
  MaterialPageRoute(
    builder: (_) => ExerciseEditor(item: item, hasGoal: hasGoal),
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
    final goal = await ref.read(goalProvider(item.exercise.id).future);
    if (!mounted) return;
    await openExerciseEditor(context, item: item, hasGoal: goal != null);
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
            else
              PopupMenuButton<String>(
                tooltip: 'Manage ${x.name}',
                enabled: !_busy.contains(x.id),
                icon: const Icon(LucideIcons.ellipsis, size: 20),
                onSelected: (choice) async {
                  if (choice == 'archive') {
                    await _archive(x);
                  } else {
                    try {
                      await _edit(item);
                    } catch (error) {
                      if (mounted) announce(context, describeError(error));
                    }
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit exercise')),
                  PopupMenuItem(value: 'archive', child: Text('Archive')),
                ],
              ),
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

class ExerciseEditor extends ConsumerStatefulWidget {
  const ExerciseEditor({this.item, this.hasGoal = false, super.key});
  final CatalogItem? item;
  final bool hasGoal;

  @override
  ConsumerState<ExerciseEditor> createState() => _ExerciseEditorState();
}

class _ExerciseEditorState extends ConsumerState<ExerciseEditor> {
  Exercise? get _original => widget.item?.exercise;
  late final _name = TextEditingController(text: _original?.name);
  late var _measurement = _original?.measurement ?? Measurement.repetitions;
  bool _busy = false;
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
        if (mounted) Navigator.pop(context, exercise);
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

  @override
  Widget build(BuildContext context) {
    final locked = (widget.item?.count ?? 0) > 0 || widget.hasGoal;
    return ProtectDraft<Exercise>(
      dirty: _dirty,
      busy: _busy,
      child: FormLayout(
        title: _original == null ? 'New exercise' : 'Edit exercise',
        footer: ActionFooter(
          label: _original == null ? 'Create exercise' : 'Save exercise',
          busy: _busy,
          onPressed: _save,
        ),
        children: [
          const SizedBox(height: 10),
          const SectionTitle('Exercise name'),
          const SizedBox(height: 10),
          TextField(
            controller: _name,
            enabled: !_busy,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: 'e.g. Push-ups',
              labelText: 'Name',
              errorText: _error,
            ),
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
          const SizedBox(height: 14),
          Text(
            locked
                ? 'Measurement is locked while this exercise has recorded sets or a goal.'
                : 'Example entry: ${_measurement == Measurement.repetitions ? '12 reps' : '1 minute, 30 seconds'}.',
            style: context.type.bodySmall,
          ),
        ],
      ),
    );
  }
}
