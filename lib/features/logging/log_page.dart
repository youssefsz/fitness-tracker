import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../shared/domain/training.dart';
import '../../shared/widgets/ui.dart';
import '../exercises/exercise_library.dart';

class LogRequest {
  const LogRequest({this.day, this.exercise, this.entry})
    : assert(entry == null || exercise != null);
  final CalendarDay? day;
  final Exercise? exercise;
  final Entry? entry;
}

class ExercisePicker extends ConsumerStatefulWidget {
  const ExercisePicker({
    required this.onSelect,
    this.excluded = const {},
    super.key,
  });
  final ValueChanged<Exercise> onSelect;
  final Set<String> excluded;

  @override
  ConsumerState<ExercisePicker> createState() => _ExercisePickerState();
}

class _ExercisePickerState extends ConsumerState<ExercisePicker> {
  var _search = '';

  @override
  Widget build(BuildContext context) {
    final style = ref.watch(durationProvider);
    return Scaffold(
      appBar: secondaryBar(context, back: 'Cancel'),
      body: ScreenScroll(
        children: [
          const ScreenHeading(
            'Choose exercise',
            subtitle: 'What did you record?',
            top: 0,
          ),
          SearchInput(
            hint: 'Search exercises',
            onChanged: (value) =>
                setState(() => _search = normalizeName(value)),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: QuietButton('Create exercise', () async {
              final exercise = await openExerciseEditor(context);
              if (mounted && exercise != null) widget.onSelect(exercise);
            }, icon: LucideIcons.plus),
          ),
          AsyncPanel(
            ref.watch(catalogProvider),
            retry: () => ref.invalidate(catalogProvider),
            builder: (list) {
              final matches = list
                  .where(
                    (row) =>
                        !row.exercise.archived &&
                        !widget.excluded.contains(row.exercise.id) &&
                        normalizeName(row.exercise.name).contains(_search),
                  )
                  .toList();
              final recent =
                  matches.where((row) => row.lastDay != null).toList()
                    ..sort((a, b) => b.lastDay!.compareTo(a.lastDay!));
              final used = recent.take(4).map((r) => r.exercise.id).toSet();
              Widget rows(String title, Iterable<String> ids) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 14),
                  SectionTitle(title),
                  const SizedBox(height: 4),
                  for (final id in ids)
                    if (matches.firstWhere((x) => x.exercise.id == id)
                        case final row)
                      RowLink(
                        title: row.exercise.name,
                        subtitle:
                            '${row.exercise.measurement.label} · '
                            '${row.latest == null ? 'No entries yet' : 'Last set ${measure(row.latest!, row.exercise.measurement, style)}'}',
                        onTap: () {
                          ref.read(actionsProvider).select();
                          widget.onSelect(row.exercise);
                        },
                      ),
                ],
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (matches.isEmpty)
                    EmptyBlock(
                      title: _search.isNotEmpty
                          ? 'No matching exercises'
                          : 'No exercises to choose',
                      message: _search.isNotEmpty
                          ? 'Try another name or create an exercise.'
                          : 'Create an exercise for the result you want to log.',
                    ),
                  if (used.isNotEmpty && _search.isEmpty)
                    rows('Recently used', used),
                  if (matches.any(
                    (r) => _search.isNotEmpty || !used.contains(r.exercise.id),
                  ))
                    rows(
                      used.isNotEmpty && _search.isEmpty
                          ? 'More exercises'
                          : 'Exercises',
                      matches
                          .where(
                            (r) =>
                                _search.isNotEmpty ||
                                !used.contains(r.exercise.id),
                          )
                          .map((r) => r.exercise.id),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class LogPage extends ConsumerStatefulWidget {
  const LogPage({this.request, super.key});
  final LogRequest? request;

  @override
  ConsumerState<LogPage> createState() => _LogPageState();
}

class _LogPageState extends ConsumerState<LogPage> {
  final _groups = <_ExerciseInput>[];
  final _form = GlobalKey<FormState>();
  late CalendarDay _day;
  bool _busy = false, _attempted = false, _confirming = false;
  String? _error;
  Entry? get _entry => widget.request?.entry;

  @override
  void initState() {
    super.initState();
    _day =
        _entry?.day ??
        widget.request?.day ??
        CalendarDay.fromDate(ref.read(nowProvider)());
    if (widget.request?.exercise case final exercise?) {
      _groups.add(_ExerciseInput(exercise, _entry));
    }
  }

  @override
  void dispose() {
    for (final group in _groups) {
      group.dispose();
    }
    super.dispose();
  }

  bool get _dirty =>
      _day != (_entry?.day ?? widget.request?.day ?? ref.read(todayProvider)) ||
      _groups.length > 1 ||
      _groups.any((group) => group.dirty);

  void _select(Exercise exercise) {
    if (_groups.any((g) => g.exercise.id == exercise.id)) return;
    setState(() => _groups.add(_ExerciseInput(exercise, null)));
  }

  Future<void> _addExercise() async {
    FocusScope.of(context).unfocus();
    final selected = await Navigator.of(context).push<Exercise>(
      MaterialPageRoute(
        builder: (route) => ExercisePicker(
          excluded: _groups.map((g) => g.exercise.id).toSet(),
          onSelect: (x) => Navigator.pop(route, x),
        ),
      ),
    );
    if (mounted && selected != null) _select(selected);
  }

  Future<void> _removeGroup(_ExerciseInput group) async {
    if (_busy) return;
    if (group.dirty) {
      final discard = await confirmAction(
        context,
        title: 'Remove ${group.exercise.name}?',
        message:
            'The unsaved sets and notes for this exercise will be discarded.',
        label: 'Remove',
        destructive: true,
      );
      if (!mounted || !discard) return;
    }
    setState(() => _groups.remove(group));
    WidgetsBinding.instance.addPostFrameCallback((_) => group.dispose());
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _attempted = true;
      _error = null;
    });
    if (!_form.currentState!.validate()) {
      setState(() => _error = 'Check the highlighted set values.');
      final invalid = _groups
          .expand((g) => g.sets)
          .where((s) => s.value == null)
          .firstOrNull;
      invalid?.focusInvalid();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final drafts = [
      for (final group in _groups)
        EntryDraft(
          exerciseId: group.exercise.id,
          day: _day,
          notes: group.notes.text,
          sets: group.sets.map((s) => (id: s.id, value: s.value!)),
        ),
    ];
    try {
      await ref.read(actionsProvider).log(drafts, original: _entry);
      if (mounted) {
        announce(context, _entry == null ? 'Entry saved.' : 'Changes saved.');
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = describeError(
            error,
            fallback: 'Couldn’t save your sets. Your draft is still here.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_busy || _confirming) return;
    _confirming = true;
    try {
      final confirmed = await confirmAction(
        context,
        title: 'Delete this entry?',
        message:
            'This removes every set and the note for ${_groups.single.exercise.name} on ${fullDay(_entry!.day)}.',
        label: 'Delete entry',
        destructive: true,
      );
      if (!mounted || !confirmed) return;
      setState(() => _busy = true);
      await ref.read(repositoryProvider).deleteEntry(_entry!.id);
      if (mounted) {
        announce(context, 'Entry deleted.');
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error));
    } finally {
      _confirming = false;
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  Future<void> _changeDay(CalendarDay today) async {
    FocusScope.of(context).unfocus();
    final picked = await pickDay(
      context,
      _day,
      latest: today,
      title: 'Activity date',
    );
    if (mounted && picked != null) {
      ref.read(actionsProvider).select();
      setState(() => _day = picked);
    }
  }

  void _addSet(_ExerciseInput group) {
    final set = _SetInput(group.exercise.measurement, null);
    setState(() => group.sets.add(set));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) set.firstFocus.requestFocus();
    });
  }

  void _removeSet(_ExerciseInput group, _SetInput set) {
    setState(() => group.sets.remove(set));
    WidgetsBinding.instance.addPostFrameCallback((_) => set.dispose());
  }

  void _next(_ExerciseInput group, int index) {
    final next = group.sets.elementAtOrNull(index + 1);
    if (next != null) {
      next.firstFocus.requestFocus();
    } else {
      FocusScope.of(context).unfocus();
    }
  }

  Widget _group(_ExerciseInput input, DurationStyle style) {
    final timed = input.exercise.measurement == Measurement.duration;
    final valid = input.sets.map((s) => s.value).nonNulls.toList();
    return Column(
      key: ObjectKey(input),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(input.exercise.name, style: context.type.titleLarge),
                  const SizedBox(height: 2),
                  Text(
                    input.exercise.measurement.label,
                    style: context.type.bodySmall,
                  ),
                ],
              ),
            ),
            if (_groups.length > 1)
              RoundControl(
                LucideIcons.x,
                'Remove ${input.exercise.name}',
                _busy ? null : () => _removeGroup(input),
              ),
          ],
        ),
        const SizedBox(height: 10),
        for (final (index, set) in input.sets.indexed)
          Padding(
            key: ObjectKey(set),
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 40,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 13),
                    child: Text(
                      '${index + 1}',
                      style: context.type.titleSmall,
                      semanticsLabel: 'Set ${index + 1}',
                    ),
                  ),
                ),
                Expanded(
                  child: TextFormField(
                    controller: set.first,
                    focusNode: set.firstFocus,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textInputAction: timed || index < input.sets.length - 1
                        ? TextInputAction.next
                        : TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: timed ? 'Minutes' : 'Reps',
                      hintText: timed ? '0' : null,
                    ),
                    validator: (_) => set.firstError,
                    onChanged: (_) => setState(() {}),
                    onFieldSubmitted: (_) => timed
                        ? set.secondFocus.requestFocus()
                        : _next(input, index),
                  ),
                ),
                if (timed) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: set.second,
                      focusNode: set.secondFocus,
                      enabled: !_busy,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textInputAction: index < input.sets.length - 1
                          ? TextInputAction.next
                          : TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Seconds',
                        hintText: '0',
                      ),
                      validator: (_) => set.secondError,
                      onChanged: (_) => setState(() {}),
                      onFieldSubmitted: (_) => _next(input, index),
                    ),
                  ),
                ],
                RoundControl(
                  LucideIcons.circleMinus,
                  'Remove set ${index + 1}',
                  input.sets.length > 1 && !_busy
                      ? () => _removeSet(input, set)
                      : null,
                ),
              ],
            ),
          ),
        QuietButton(
          'Add set',
          _busy || input.sets.length >= maxSetsPerEntry
              ? null
              : () => _addSet(input),
          icon: LucideIcons.plus,
        ),
        if (valid.isNotEmpty)
          Text(
            '${_entry == null ? '' : 'Latest ${measure(valid.last, input.exercise.measurement, style)} · '}'
            'Best ${measure(valid.reduce((a, b) => a > b ? a : b), input.exercise.measurement, style)} · '
            'Total ${measure(valid.fold(0, (a, b) => a + b), input.exercise.measurement, style)}',
            style: context.type.bodySmall,
          ),
        if (input.showNotes) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: input.notes,
            enabled: !_busy,
            minLines: 2,
            maxLines: 5,
            maxLength: maxNotes,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              hintText: 'Anything worth remembering?',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ] else
          QuietButton(
            'Add a note',
            _busy ? null : () => setState(() => input.showNotes = true),
          ),
        const Divider(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayProvider);
    final style = ref.watch(durationProvider);
    if (_groups.isEmpty) return ExercisePicker(onSelect: _select);
    final count = _groups.fold(0, (sum, group) => sum + group.sets.length);
    return ProtectDraft<void>(
      dirty: _dirty,
      busy: _busy,
      child: Form(
        key: _form,
        autovalidateMode: _attempted
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: FormLayout(
          title: _entry == null ? 'Add entry' : 'Edit entry',
          footer: ActionFooter(
            label: _entry == null
                ? 'Save $count ${count == 1 ? 'set' : 'sets'}'
                : 'Save changes',
            busy: _busy,
            onPressed: _save,
            secondary:
                _entry == null || MediaQuery.viewInsetsOf(context).bottom > 0
                ? null
                : QuietButton(
                    'Delete entry',
                    _busy ? null : _delete,
                    danger: true,
                  ),
          ),
          children: [
            RowLink(
              title: fullDay(_day),
              subtitle: _day == today ? 'Today' : 'Activity date',
              leading: const Icon(LucideIcons.calendarDays, size: 20),
              detail: 'Change',
              icon: LucideIcons.chevronRight,
              onTap: _busy ? null : () => _changeDay(today),
            ),
            for (final group in _groups) ...[
              const SizedBox(height: 18),
              _group(group, style),
            ],
            if (_entry == null)
              Align(
                alignment: Alignment.centerLeft,
                child: QuietButton(
                  'Add another exercise',
                  _busy ? null : _addExercise,
                  icon: LucideIcons.plus,
                ),
              ),
            FormProblem(_error),
          ],
        ),
      ),
    );
  }
}

class _ExerciseInput {
  _ExerciseInput(this.exercise, Entry? original)
    : notes = TextEditingController(text: original?.notes),
      originalNotes = original?.notes ?? '',
      originalSets = original?.sets,
      showNotes = original != null,
      sets = [
        if (original == null)
          _SetInput(exercise.measurement, null)
        else
          for (final set in original.sets) _SetInput(exercise.measurement, set),
      ];
  final Exercise exercise;
  final TextEditingController notes;
  final String originalNotes;
  final List<RecordedSet>? originalSets;
  final List<_SetInput> sets;
  bool showNotes;

  bool get dirty {
    if (notes.text != originalNotes) return true;
    final original = originalSets;
    if (original == null) {
      return sets.length != 1 ||
          sets.any((s) => s.first.text.isNotEmpty || s.second.text.isNotEmpty);
    }
    return sets.length != original.length ||
        sets.indexed.any((item) {
          final (i, set) = item;
          return set.id != original[i].id || set.value != original[i].value;
        });
  }

  void dispose() {
    notes.dispose();
    for (final set in sets) {
      set.dispose();
    }
  }
}

class _SetInput {
  _SetInput(this.measurement, RecordedSet? original)
    : id = original?.id,
      first = TextEditingController(
        text: original == null
            ? ''
            : measurement == Measurement.duration
            ? '${original.value ~/ 60}'
            : '${original.value}',
      ),
      second = TextEditingController(
        text: original == null || measurement != Measurement.duration
            ? ''
            : '${original.value % 60}',
      );

  final Measurement measurement;
  final String? id;
  final TextEditingController first, second;
  final firstFocus = FocusNode(), secondFocus = FocusNode();

  int? get _minutes => int.tryParse(first.text.isEmpty ? '0' : first.text);
  int? get _seconds => int.tryParse(second.text.isEmpty ? '0' : second.text);
  int? get _duration =>
      _minutes == null || _minutes! > maxSetValue ~/ 60 || _seconds == null
      ? null
      : _minutes! * 60 + _seconds!;

  String? get firstError {
    if (measurement == Measurement.repetitions) {
      return setValueError(int.tryParse(first.text));
    }
    return _minutes == null || _minutes! > maxSetValue ~/ 60
        ? 'Enter fewer minutes.'
        : null;
  }

  String? get secondError {
    if (measurement == Measurement.repetitions) return null;
    if (_seconds == null || _seconds! > 59) return 'Enter 0 to 59.';
    if (firstError == null && (_duration == 0 || _duration! > maxSetValue)) {
      return 'Enter a valid duration.';
    }
    return null;
  }

  int? get value => firstError != null || secondError != null
      ? null
      : measurement == Measurement.repetitions
      ? int.tryParse(first.text)
      : _duration;

  void focusInvalid() =>
      (firstError != null ? firstFocus : secondFocus).requestFocus();

  void dispose() {
    first.dispose();
    second.dispose();
    firstFocus.dispose();
    secondFocus.dispose();
  }
}
