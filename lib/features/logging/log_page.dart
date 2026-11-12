import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../shared/domain/training.dart';
import '../../shared/widgets/draft_sheet.dart';
import '../../shared/widgets/exercise_icon.dart';
import '../../shared/widgets/ui.dart';
import '../exercises/exercise_library.dart';

class LogRequest {
  const LogRequest({this.day, this.exercise, this.entry})
    : assert(entry == null || exercise != null);
  final CalendarDay? day;
  final Exercise? exercise;
  final Entry? entry;
}

Future<void> showLogSheet(BuildContext context, {LogRequest? request}) =>
    Navigator.of(context, rootNavigator: true).push<void>(
      DraftSheetRoute<void>(
        context: context,
        builder: (_) => LogPage(request: request),
      ),
    );

class _ExercisePicker extends ConsumerWidget {
  const _ExercisePicker({
    required this.onSelect,
    required this.onCreate,
    required this.search,
    required this.excluded,
    this.selected,
    super.key,
  });
  final ValueChanged<Exercise> onSelect;
  final VoidCallback onCreate;
  final TextEditingController search;
  final Set<String> excluded;
  final String? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(durationProvider);
    final catalog = ref.watch(catalogProvider);
    return ScreenScroll(
      scrollKey: const PageStorageKey('log-exercises'),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: Space.md),
          child: Text('What did you record?', style: context.type.bodyMedium),
        ),
        SearchInput(hint: 'Search exercises', controller: search),
        Align(
          alignment: Alignment.centerLeft,
          child: QuietButton(
            'Create exercise',
            onCreate,
            icon: LucideIcons.plus,
          ),
        ),
        ValueListenableBuilder(
          valueListenable: search,
          builder: (context, input, _) {
            final query = normalizeName(input.text);
            return AsyncPanel(
              catalog,
              retry: () => ref.invalidate(catalogProvider),
              builder: (list) {
                final matches = list
                    .where(
                      (row) =>
                          !row.exercise.archived &&
                          !excluded.contains(row.exercise.id) &&
                          normalizeName(row.exercise.name).contains(query),
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
                          leading: ExerciseIcon(row.exercise.name),
                          subtitle:
                              '${row.exercise.measurement.label} · '
                              '${row.latest == null ? 'No entries yet' : 'Last set ${measure(row.latest!, row.exercise.measurement, style)}'}',
                          icon: selected == id ? LucideIcons.check : null,
                          onTap: () {
                            ref.read(actionsProvider).select();
                            onSelect(row.exercise);
                          },
                        ),
                  ],
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (matches.isEmpty)
                      EmptyBlock(
                        title: query.isNotEmpty
                            ? 'No matching exercises'
                            : 'No exercises to choose',
                        message: query.isNotEmpty
                            ? 'Try another name or create an exercise.'
                            : 'Create an exercise for the result you want to log.',
                      ),
                    if (used.isNotEmpty && query.isEmpty)
                      rows('Recently used', used),
                    if (matches.any(
                      (r) => query.isNotEmpty || !used.contains(r.exercise.id),
                    ))
                      rows(
                        used.isNotEmpty && query.isEmpty
                            ? 'More exercises'
                            : 'Exercises',
                        matches
                            .where(
                              (r) =>
                                  query.isNotEmpty ||
                                  !used.contains(r.exercise.id),
                            )
                            .map((r) => r.exercise.id),
                      ),
                  ],
                );
              },
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.only(top: Space.lg),
          child: Text(
            'Saved exercises are always available here.',
            style: context.type.bodySmall,
          ),
        ),
      ],
    );
  }
}

enum _LogStep { chooseExercise, sets, addExercise, createExercise }

class LogPage extends ConsumerStatefulWidget {
  const LogPage({this.request, super.key});
  final LogRequest? request;

  @override
  ConsumerState<LogPage> createState() => _LogPageState();
}

class _LogPageState extends ConsumerState<LogPage> {
  final _groups = <_ExerciseInput>[];
  final _form = GlobalKey<FormState>();
  final _search = TextEditingController();
  final _additionalSearch = TextEditingController();
  late _LogStep _step;
  late _LogStep _pickerBeforeCreate;
  _ExerciseInput? _selectedGroup;
  late CalendarDay _day;
  bool _busy = false, _attempted = false, _confirming = false;
  String? _error;
  Entry? get _entry => widget.request?.entry;
  DraftSheetRoute<void> get _sheetRoute =>
      ModalRoute.of(context)! as DraftSheetRoute<void>;

  @override
  void initState() {
    super.initState();
    _day =
        _entry?.day ??
        widget.request?.day ??
        CalendarDay.fromDate(ref.read(nowProvider)());
    if (widget.request?.exercise case final exercise?) {
      final group = _ExerciseInput(exercise, _entry);
      _groups.add(group);
      _selectedGroup = group;
    }
    _step = _groups.isEmpty ? _LogStep.chooseExercise : _LogStep.sets;
  }

  @override
  void dispose() {
    _search.dispose();
    _additionalSearch.dispose();
    for (final group in _groups) {
      group.dispose();
    }
    super.dispose();
  }

  bool get _dirty =>
      _day != (_entry?.day ?? widget.request?.day ?? ref.read(todayProvider)) ||
      _groups.length > 1 ||
      _groups.any((group) => group.dirty);

  void _goTo(_LogStep step) {
    FocusScope.of(context).unfocus();
    setState(() => _step = step);
  }

  Future<void> _select(Exercise exercise) async {
    if (_busy || _confirming || _step == _LogStep.sets) return;
    final replacing = _step == _LogStep.chooseExercise ? _selectedGroup : null;
    if (_groups.any(
      (group) => group != replacing && group.exercise.id == exercise.id,
    )) {
      return;
    }

    final changesUnit =
        replacing != null &&
        replacing.exercise.measurement != exercise.measurement;
    if (changesUnit && replacing.hasEnteredValues) {
      _confirming = true;
      final confirmed = await confirmAction(
        context,
        title: 'Switch to ${exercise.name}?',
        message:
            'This exercise uses different units. The set values for '
            '${replacing.exercise.name} will be cleared. Your date, notes, '
            'and other exercises stay in the draft.',
        label: 'Switch exercise',
      );
      _confirming = false;
      if (!mounted || !confirmed) return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      if (replacing == null) {
        final group = _ExerciseInput(exercise, null);
        _groups.add(group);
        _selectedGroup = group;
      } else if (changesUnit) {
        final replacement = _ExerciseInput(exercise, null)
          ..notes.text = replacing.notes.text
          ..showNotes = replacing.showNotes;
        _groups[_groups.indexOf(replacing)] = replacement;
        _selectedGroup = replacement;
        replacing.dispose();
      } else {
        replacing.exercise = exercise;
      }
      _error = null;
      _step = _LogStep.sets;
    });
  }

  void _addExercise() {
    _additionalSearch.clear();
    _goTo(_LogStep.addExercise);
  }

  void _createExercise() {
    _pickerBeforeCreate = _step;
    _goTo(_LogStep.createExercise);
  }

  void _useCreatedExercise(Exercise exercise) {
    _goTo(_pickerBeforeCreate);
    _select(exercise);
  }

  Future<bool> _discardDraft() async {
    _confirming = true;
    try {
      return await confirmAction(
        context,
        title: 'Discard changes?',
        message: 'Your unsaved changes will be lost.',
        label: 'Discard',
        destructive: true,
      );
    } finally {
      _confirming = false;
    }
  }

  Future<void> _close({
    bool editorDirty = false,
    bool editorBusy = false,
  }) async {
    if (_busy || _confirming || editorBusy) return;
    FocusScope.of(context).unfocus();
    if ((_dirty || editorDirty) && !await _discardDraft()) return;
    if (mounted) _sheetRoute.finish();
  }

  Future<void> _back({
    bool editorDirty = false,
    bool editorBusy = false,
  }) async {
    if (_busy || _confirming || editorBusy) return;
    switch (_step) {
      case _LogStep.sets:
        _goTo(_LogStep.chooseExercise);
      case _LogStep.addExercise:
        _goTo(_LogStep.sets);
      case _LogStep.chooseExercise:
        await _close();
      case _LogStep.createExercise:
        FocusScope.of(context).unfocus();
        if (editorDirty && !await _discardDraft()) return;
        if (mounted) _goTo(_pickerBeforeCreate);
    }
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
    setState(() {
      _groups.remove(group);
      if (_selectedGroup == group) _selectedGroup = _groups.lastOrNull;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => group.dispose());
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _attempted = true;
      _error = null;
    });
    final invalid = _groups
        .expand((group) => group.sets)
        .where((set) => set.value == null)
        .firstOrNull;
    if (!_form.currentState!.validate() || invalid != null) {
      setState(() => _error = 'Check the set values before saving.');
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
        if (_entry == null) {
          _sheetRoute.finish();
        } else {
          Navigator.pop(context);
        }
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
            ExerciseIcon(input.exercise.name),
            const SizedBox(width: Space.sm),
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
            if (_groups.length > 1) ...[
              RoundControl(
                LucideIcons.pencil,
                'Change ${input.exercise.name}',
                _busy
                    ? null
                    : () {
                        _selectedGroup = input;
                        _goTo(_LogStep.chooseExercise);
                      },
              ),
              RoundControl(
                LucideIcons.x,
                'Remove ${input.exercise.name}',
                _busy ? null : () => _removeGroup(input),
              ),
            ],
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: Space.md, bottom: Space.sm),
          child: ExcludeSemantics(
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Text('Set', style: context.type.labelMedium),
                ),
                Expanded(
                  child: Text(
                    timed ? 'Minutes' : 'Reps',
                    style: context.type.labelMedium,
                  ),
                ),
                if (timed) ...[
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text('Seconds', style: context.type.labelMedium),
                  ),
                ],
                const SizedBox(width: Space.target),
              ],
            ),
          ),
        ),
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
                      floatingLabelBehavior: FloatingLabelBehavior.never,
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
                        floatingLabelBehavior: FloatingLabelBehavior.never,
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
        if (valid.isNotEmpty) ...[
          Text(
            '${_entry == null ? '' : 'Latest ${measure(valid.last, input.exercise.measurement, style)} · '}'
            'Best ${measure(valid.reduce((a, b) => a > b ? a : b), input.exercise.measurement, style)}'
            '${_entry == null ? ' · ' : '\n'}'
            'Total ${measure(valid.fold(0, (a, b) => a + b), input.exercise.measurement, style)}',
            style: context.type.bodySmall,
          ),
          const SizedBox(height: Space.sm),
        ],
        if (_groups.length > 1) _notes(input),
        const Divider(),
      ],
    );
  }

  Widget _notes(_ExerciseInput input) => input.showNotes
      ? Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _entry == null ? 'Notes (optional)' : 'Notes',
                style: context.type.titleSmall,
              ),
              const SizedBox(height: Space.sm),
              TextFormField(
                controller: input.notes,
                enabled: !_busy,
                minLines: 2,
                maxLines: 5,
                maxLength: maxNotes,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  hintText: 'Anything worth remembering?',
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        )
      : Align(
          alignment: AlignmentDirectional.centerStart,
          child: QuietButton(
            'Add a note',
            _busy ? null : () => setState(() => input.showNotes = true),
          ),
        );

  Widget _sheet({
    required String title,
    required Widget child,
    Widget? footer,
    bool Function()? editorDirty,
    bool Function()? editorBusy,
  }) {
    bool isEditorDirty() => editorDirty?.call() ?? false;
    bool isEditorBusy() => editorBusy?.call() ?? false;
    final busy = _busy || isEditorBusy();
    final firstStep = _step == _LogStep.chooseExercise;
    final route = _sheetRoute;
    void close() =>
        _close(editorDirty: isEditorDirty(), editorBusy: isEditorBusy());
    void back() =>
        _back(editorDirty: isEditorDirty(), editorBusy: isEditorBusy());
    bool hasProtectedDraft() =>
        _busy || isEditorBusy() || _confirming || isEditorDirty() || _dirty;
    route.hasProtectedDraft = hasProtectedDraft;
    route.onDismissBlocked = close;
    return PopScope<void>(
      canPop: firstStep && !hasProtectedDraft(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) back();
      },
      child: SheetLayout(
        title: title,
        back: firstStep || busy ? null : back,
        closeLabel: 'Cancel entry',
        close: busy ? null : close,
        footer: footer,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_step == _LogStep.createExercise) {
      return ExerciseEditor.inSheet(
        onCreated: _useCreatedExercise,
        layout:
            ({
              required dirty,
              required busy,
              required child,
              required footer,
            }) => _sheet(
              title: 'New exercise',
              editorDirty: dirty,
              editorBusy: busy,
              child: child,
              footer: footer,
            ),
      );
    }
    final today = ref.watch(todayProvider);
    final style = ref.watch(durationProvider);
    final count = _groups.fold(0, (sum, group) => sum + group.sets.length);
    final fields = <Widget>[
      RowLink(
        title: fullDay(_day),
        subtitle: _entry == null && _day == today ? 'Today' : null,
        leading: _entry == null
            ? const Icon(LucideIcons.calendarDays, size: 20)
            : null,
        detail: 'Change',
        detailStyle: context.type.labelLarge?.copyWith(
          color: context.colors.green,
        ),
        showChevron: false,
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
      if (_groups.length == 1) _notes(_groups.single),
    ];
    final footer = ActionFooter(
      label: _entry == null
          ? 'Save $count ${count == 1 ? 'set' : 'sets'}'
          : 'Save changes',
      busy: _busy,
      onPressed: _save,
      secondary: _entry == null || MediaQuery.viewInsetsOf(context).bottom > 0
          ? null
          : QuietButton('Delete entry', _busy ? null : _delete, danger: true),
    );
    final autovalidate = _attempted
        ? AutovalidateMode.onUserInteraction
        : AutovalidateMode.disabled;

    if (_entry != null) {
      return ProtectDraft<void>(
        dirty: _dirty,
        busy: _busy,
        child: Form(
          key: _form,
          autovalidateMode: autovalidate,
          child: FormLayout(
            title: 'Edit entry',
            footer: footer,
            children: [...fields, FormProblem(_error)],
          ),
        ),
      );
    }

    final choosing = _step != _LogStep.sets;
    final adding = _step == _LogStep.addExercise;
    final current = _selectedGroup;
    return _sheet(
      title: choosing ? 'Choose exercise' : 'Add entry',
      footer: choosing
          ? !adding && current != null
                ? ActionFooter(
                    label: 'Continue to sets',
                    onPressed: () => _goTo(_LogStep.sets),
                  )
                : null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: FormProblem(_error),
                  ),
                footer,
              ],
            ),
      child: choosing
          ? _ExercisePicker(
              key: ValueKey(_step),
              onSelect: _select,
              onCreate: _createExercise,
              search: adding ? _additionalSearch : _search,
              selected: adding ? null : current?.exercise.id,
              excluded: {
                for (final group in _groups)
                  if (adding || group != current) group.exercise.id,
              },
            )
          : Form(
              key: _form,
              autovalidateMode: autovalidate,
              child: ScreenScroll(
                scrollKey: const PageStorageKey('log-sets'),
                children: fields,
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
  Exercise exercise;
  final TextEditingController notes;
  final String originalNotes;
  final List<RecordedSet>? originalSets;
  final List<_SetInput> sets;
  bool showNotes;

  bool get hasEnteredValues => sets.any(
    (set) => set.first.text.isNotEmpty || set.second.text.isNotEmpty,
  );

  bool get dirty {
    if (notes.text != originalNotes) return true;
    final original = originalSets;
    if (original == null) {
      return sets.length != 1 || hasEnteredValues;
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
