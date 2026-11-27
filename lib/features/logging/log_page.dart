import 'dart:async';

import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/database/tracker_repository.dart'
    show CatalogItem, PreviousSet;
import '../../shared/domain/training.dart';
import '../../shared/widgets/draft_sheet.dart';
import '../../shared/widgets/exercise_icon.dart';
import '../../shared/widgets/collapsing_page.dart';
import '../../shared/widgets/ui.dart';
import '../exercises/exercise_library.dart';

class LogRequest {
  const LogRequest({
    this.day,
    this.exercise,
    this.entry,
    this.repeatEntries = const [],
    this.repeatSourceDay,
    this.skippedArchivedCount = 0,
  }) : assert(entry == null || exercise != null);
  final CalendarDay? day;
  final Exercise? exercise;
  final Entry? entry;
  final List<RepeatEntry> repeatEntries;
  final CalendarDay? repeatSourceDay;
  final int skippedArchivedCount;
}

typedef RepeatEntry = ({Exercise exercise, Entry entry});

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
    required this.liveWorkout,
    this.onStartLiveWorkout,
    this.selected,
    super.key,
  });
  final ValueChanged<CatalogItem> onSelect;
  final VoidCallback onCreate;
  final TextEditingController search;
  final Set<String> excluded;
  final bool liveWorkout;
  final VoidCallback? onStartLiveWorkout;
  final String? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(durationProvider);
    final catalog = ref.watch(catalogProvider);
    return ScreenScroll(
      scrollKey: const PageStorageKey('log-exercises'),
      children: [
        if (!liveWorkout)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.md),
            child: Text('What did you record?', style: context.type.bodyMedium),
          ),
        SearchInput(hint: 'Search exercises', controller: search),
        Wrap(
          spacing: Space.sm,
          children: [
            QuietButton('Create exercise', onCreate, icon: LucideIcons.plus),
            if (onStartLiveWorkout case final start?)
              QuietButton('Start live workout', start, icon: LucideIcons.play),
          ],
        ),
        ValueListenableBuilder(
          valueListenable: search,
          builder: (context, input, _) {
            final query = normalizeName(input.text);
            return AsyncPanel(
              catalog,
              loadingLabel: 'Loading exercises',
              loading: const SkeletonRows(),
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
                              '${row.latest == null ? 'No entries yet' : 'Latest ${measure(row.latest!, row.exercise.measurement, style, reps: row.latestReps)}'}',
                          icon: selected == id ? LucideIcons.check : null,
                          onTap: () {
                            ref.read(actionsProvider).select();
                            onSelect(row);
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
                        secondary: query.isEmpty
                            ? null
                            : QuietButton('Clear search', search.clear),
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

enum _RestTimerOption {
  minute('1 minute', 60),
  minuteAndHalf('1 minute 30 seconds', 90),
  twoMinutes('2 minutes', 120),
  threeMinutes('3 minutes', 180),
  fiveMinutes('5 minutes', 300),
  off('Turn off rest timer');

  const _RestTimerOption(this.label, [this.seconds]);

  final String label;
  final int? seconds;
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
  final _search = TextEditingController();
  final _additionalSearch = TextEditingController();
  final _restSeconds = ValueNotifier<int?>(null);
  Timer? _restTimer;
  int _restDuration = 0;
  int _nextRestDuration = 90;
  DateTime? _restDeadline;
  late _LogStep _step;
  late _LogStep _pickerBeforeCreate;
  _ExerciseInput? _selectedGroup;
  late CalendarDay _day;
  bool _liveWorkout = false;
  bool _busy = false, _attempted = false, _confirming = false;
  String? _error;
  Entry? get _entry => widget.request?.entry;
  DraftSheetRoute<void> get _sheetRoute =>
      ModalRoute.of(context)! as DraftSheetRoute<void>;

  @override
  void initState() {
    super.initState();
    final request = widget.request;
    final repeatEntries = request?.repeatEntries ?? const <RepeatEntry>[];
    if (repeatEntries.isNotEmpty) {
      _day = CalendarDay.fromDate(ref.read(nowProvider)());
      for (final repeated in repeatEntries) {
        _groups.add(_ExerciseInput.repeat(repeated.exercise, repeated.entry));
      }
      _selectedGroup = _groups.first;
    } else {
      _day =
          _entry?.day ??
          request?.day ??
          CalendarDay.fromDate(ref.read(nowProvider)());
      if (request?.exercise case final exercise?) {
        final group = _ExerciseInput(exercise, _entry);
        _groups.add(group);
        _selectedGroup = group;
      }
    }
    _step = _groups.isEmpty ? _LogStep.chooseExercise : _LogStep.sets;
  }

  @override
  void dispose() {
    _restTimer?.cancel();
    _restSeconds.dispose();
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
      _groups.any(
        (group) => group.dirty || group.sets.any((set) => set.completed),
      );

  void _goTo(_LogStep step) {
    FocusScope.of(context).unfocus();
    setState(() => _step = step);
  }

  void _startLiveWorkout() {
    FocusScope.of(context).unfocus();
    setState(() => _liveWorkout = true);
  }

  Future<void> _select(Exercise exercise, {bool knownNoHistory = false}) async {
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
    final dropsSets =
        replacing != null && !exercise.trackSets && replacing.sets.length > 1;
    if (replacing != null &&
        ((changesUnit && replacing.hasEnteredValues) || dropsSets)) {
      _confirming = true;
      final confirmed = await confirmAction(
        context,
        title: 'Switch to ${exercise.name}?',
        message: changesUnit
            ? 'This exercise uses a different measurement. The values for ${replacing.exercise.name} will be cleared.'
            : 'This exercise logs one result. Only the first value will carry over.',
        label: 'Switch exercise',
      );
      _confirming = false;
      if (!mounted || !confirmed) return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      if (replacing == null) {
        final group = _ExerciseInput(
          exercise,
          null,
          knownNoHistory: knownNoHistory,
        );
        _groups.add(group);
        _selectedGroup = group;
      } else if (changesUnit) {
        final replacement =
            _ExerciseInput(exercise, null, knownNoHistory: knownNoHistory)
              ..notes.text = replacing.notes.text
              ..showNotes = replacing.showNotes;
        _groups[_groups.indexOf(replacing)] = replacement;
        _selectedGroup = replacement;
        replacing.dispose();
      } else {
        if (dropsSets) {
          for (final set in replacing.sets.skip(1)) {
            set.dispose();
          }
          replacing.sets.removeRange(1, replacing.sets.length);
          replacing.activeSet = replacing.sets.single;
        }
        replacing.exercise = exercise;
        replacing.knownNoHistory = knownNoHistory;
        for (final set in replacing.sets) {
          set.completed = false;
        }
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
    _select(exercise, knownNoHistory: true);
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
        if (_liveWorkout && _groups.isEmpty) {
          FocusScope.of(context).unfocus();
          setState(() => _liveWorkout = false);
        } else {
          await _close();
        }
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
    if (_busy || _confirming) return;
    if (_liveWorkout) {
      await _finishLiveWorkout();
      return;
    }
    setState(() {
      _attempted = true;
      _error = null;
    });
    final formValid = _form.currentState!.validate();
    for (final group in _groups) {
      final invalid = group.sets.where((set) => set.value == null).firstOrNull;
      if (invalid != null) {
        setState(() => _error = 'Check the values before saving.');
        _activateSet(group, invalid, invalid: true);
        return;
      }
    }
    if (!formValid) {
      setState(() => _error = 'Check the values before saving.');
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
          sets: group.sets.map(
            (s) => (id: s.id, value: s.value!, reps: s.reps),
          ),
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
            fallback: 'Couldn’t save your activity. Your draft is still here.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finishLiveWorkout() async {
    final completedCount = _groups.fold<int>(
      0,
      (sum, group) => sum + group.sets.where((set) => set.completed).length,
    );
    if (completedCount == 0) {
      setState(() => _error = 'Complete at least one set before finishing.');
      return;
    }

    final incompleteCount =
        _groups.fold<int>(0, (sum, group) => sum + group.sets.length) -
        completedCount;
    if (incompleteCount > 0) {
      _confirming = true;
      final confirmed = await confirmAction(
        context,
        title: 'Skip incomplete sets?',
        message:
            'Finish with $completedCount completed ${completedCount == 1 ? 'set' : 'sets'} and skip $incompleteCount incomplete ${incompleteCount == 1 ? 'set' : 'sets'}?',
        label: 'Finish workout',
      );
      _confirming = false;
      if (!mounted || !confirmed) return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final drafts = [
      for (final group in _groups)
        if (group.sets.any((set) => set.completed))
          EntryDraft(
            exerciseId: group.exercise.id,
            day: _day,
            notes: group.notes.text,
            sets: group.sets
                .where((set) => set.completed)
                .map((set) => (id: set.id, value: set.value!, reps: set.reps)),
          ),
    ];
    try {
      await ref.read(actionsProvider).log(drafts, original: _entry);
      if (mounted) {
        announce(context, 'Workout saved.');
        _sheetRoute.finish();
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = describeError(
            error,
            fallback: 'Couldn’t save your workout. Your draft is still here.',
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

  void _activateSet(
    _ExerciseInput group,
    _SetInput set, {
    bool invalid = false,
    bool unlock = false,
  }) {
    setState(() {
      group.activeSet = set;
      if (_liveWorkout && unlock) set.completed = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || group.activeSet != set || !group.sets.contains(set)) {
        return;
      }
      if (invalid) {
        set.focusInvalid();
      } else {
        set.firstFocus.requestFocus();
      }
    });
  }

  void _addSet(_ExerciseInput group) {
    final set = _SetInput(group.exercise.measurement, null);
    group.sets.add(set);
    _activateSet(group, set);
  }

  void _completeSet(_ExerciseInput group, _SetInput set) {
    if (_busy || set.completed) return;
    setState(() {
      _attempted = true;
      _error = null;
    });
    if (set.value != null) {
      FocusScope.of(context).unfocus();
      setState(() => set.completed = true);
      return;
    }
    setState(() => _error = 'Check the values before completing the set.');
    _activateSet(group, set, invalid: true);
  }

  void _removeSet(_ExerciseInput group, _SetInput set) {
    setState(() {
      final index = group.sets.indexOf(set);
      group.sets.removeAt(index);
      if (group.activeSet == set) {
        group.activeSet = group.sets.elementAtOrNull(index) ?? group.sets.last;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => set.dispose());
  }

  Future<void> _chooseRestDuration() async {
    FocusScope.of(context).unfocus();
    final option = await chooseOption(context, 'Rest timer', [
      for (final value in _RestTimerOption.values)
        (value: value, label: value.label, subtitle: null),
    ]);
    if (!mounted || option == null) return;
    if (option == _RestTimerOption.off) {
      try {
        await ref.read(repositoryProvider).saveRestTimerEnabled(false);
      } catch (error) {
        if (mounted) {
          announce(
            context,
            describeError(error, fallback: 'Couldn’t turn off the rest timer.'),
          );
        }
      }
      return;
    }
    if (ref.read(restTimerEnabledProvider).value != true) return;
    _nextRestDuration = option.seconds!;
    if (!mounted) return;
    setState(() {});
  }

  void _startRest() => _setRestDeadline(
    ref.read(nowProvider)().add(Duration(seconds: _nextRestDuration)),
    _nextRestDuration,
  );

  void _adjustRest(int seconds) {
    final deadline = _restDeadline;
    if (deadline == null) return;
    final now = ref.read(nowProvider)();
    if (!deadline.isAfter(now)) return;
    final shifted = deadline.add(Duration(seconds: seconds));
    final adjusted = shifted.difference(now).inMilliseconds;
    final bounded = adjusted.clamp(1000, 3600000);
    _restDuration = (_restDuration + seconds).clamp(1, 3600);
    _restDeadline = now.add(Duration(milliseconds: bounded));
    _restSeconds.value = (bounded / 1000).ceil();
    _scheduleRestTick();
  }

  void _setRestDeadline(DateTime deadline, int duration) {
    _restDuration = duration;
    _restDeadline = deadline;
    _restSeconds.value = duration;
    _scheduleRestTick();
  }

  void _scheduleRestTick() {
    final now = ref.read(nowProvider);
    _restTimer?.cancel();
    _restTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final milliseconds = _restDeadline!.difference(now()).inMilliseconds;
      _restSeconds.value = (milliseconds / 1000).ceil().clamp(0, 3600);
      if (milliseconds <= 0) timer.cancel();
    });
  }

  void _clearRestTimer() {
    _restTimer?.cancel();
    _restDeadline = null;
    _restSeconds.value = null;
  }

  Widget _restStatus() => ValueListenableBuilder(
    valueListenable: _restSeconds,
    builder: (context, seconds, _) {
      final complete = seconds == 0;
      final timerAction = QuietButton(
        'Rest ${clockValue(_nextRestDuration)}',
        _busy ? null : _chooseRestDuration,
        icon: LucideIcons.timer,
      );
      return Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Space.formWidth),
          child: LayoutBuilder(
            builder: (context, constraints) => Padding(
              padding: EdgeInsets.symmetric(
                horizontal: Space.pageInset(constraints.maxWidth),
              ),
              child: seconds == null
                  ? OverflowBar(
                      alignment: MainAxisAlignment.spaceBetween,
                      overflowAlignment: OverflowBarAlignment.end,
                      spacing: Space.sm,
                      children: [
                        timerAction,
                        QuietButton('Start rest', _busy ? null : _startRest),
                      ],
                    )
                  : Column(
                      children: [
                        if (complete)
                          const Divider()
                        else
                          ExcludeSemantics(
                            child: LinearProgressIndicator(
                              value: seconds / _restDuration,
                              minHeight: 2,
                              borderRadius: BorderRadius.circular(1),
                              backgroundColor: context.colors.border,
                              color: context.colors.green,
                            ),
                          ),
                        OverflowBar(
                          alignment: MainAxisAlignment.spaceBetween,
                          overflowAlignment: OverflowBarAlignment.end,
                          spacing: Space.sm,
                          children: [
                            if (complete)
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  'Rest complete',
                                  style: context.type.bodySmall,
                                ),
                              )
                            else ...[
                              Semantics(
                                label:
                                    'Rest time remaining ${clockValue(seconds)}',
                                child: Text(
                                  clockValue(seconds),
                                  style: context.type.titleSmall,
                                ),
                              ),
                              QuietButton(
                                '−15 sec',
                                _busy ? null : () => _adjustRest(-15),
                              ),
                              QuietButton(
                                '+15 sec',
                                _busy ? null : () => _adjustRest(15),
                              ),
                            ],
                            Tooltip(
                              message: complete
                                  ? 'Dismiss timer'
                                  : 'Stop rest timer',
                              child: QuietButton(
                                complete ? 'Done' : 'Stop',
                                _clearRestTimer,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ),
        ),
      );
    },
  );

  Widget _valueInput(_SetInput set, {required bool autofocus}) {
    final timed = set.measurement == Measurement.duration;
    final paired = set.measurement.needsReps;

    Widget field(String label, {bool secondary = false, double size = 56}) =>
        Column(
          children: [
            LargeNumberField(
              label: label,
              controller: secondary ? set.second : set.first,
              focusNode: secondary ? set.secondFocus : set.firstFocus,
              autofocus: autofocus && !secondary,
              enabled: !_busy && (!_liveWorkout || !set.completed),
              fontSize: size,
              decimal: !secondary && set.measurement.usesWeight,
              hint: timed && secondary
                  ? '00'
                  : !secondary && set.measurement.usesWeight
                  ? '0.0'
                  : '0',
              next: !secondary && (timed || paired),
              validator: (_) => secondary ? set.secondError : set.firstError,
              onChanged: (_) => setState(() {}),
              onSubmitted: !secondary && (timed || paired)
                  ? (_) => set.secondFocus.requestFocus()
                  : (_) => FocusScope.of(context).unfocus(),
            ),
            Text(label, style: context.type.labelLarge),
          ],
        );

    if (!timed && !paired) {
      return field(set.measurement.usesWeight ? 'kg' : 'Reps');
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: timed ? 1 : 3,
          child: field(timed ? 'Minutes' : 'kg', size: timed ? 48 : 56),
        ),
        Padding(
          padding: const EdgeInsets.only(top: Space.md),
          child: Text(timed ? ':' : '×', style: context.type.headlineMedium),
        ),
        Expanded(
          flex: timed ? 1 : 2,
          child: field(
            timed ? 'Seconds' : 'Reps',
            secondary: true,
            size: timed ? 48 : 40,
          ),
        ),
      ],
    );
  }

  Widget _previousSetContext(_ExerciseInput input, DurationStyle style) {
    if (input.knownNoHistory || _isRepeatDraft) return const SizedBox.shrink();
    final filter = (
      exerciseId: input.exercise.id,
      day: _day,
      excludingEntryId: _entry?.exerciseId == input.exercise.id
          ? _entry!.id
          : null,
    );
    final previousSet = ref.watch(previousSetProvider(filter));
    if (previousSet.hasError && !previousSet.hasValue) {
      return RowLink(
        title: 'Previous',
        subtitle: 'Couldn’t load previous set',
        leading: Icon(
          LucideIcons.refreshCw,
          size: 20,
          color: context.colors.muted,
        ),
        detail: 'Retry',
        detailStyle: context.type.labelLarge?.copyWith(
          color: context.colors.green,
        ),
        showChevron: false,
        onTap: () => ref.invalidate(previousSetProvider(filter)),
      );
    }
    return AsyncPanel<PreviousSet?>(
      previousSet,
      loadingLabel: 'Loading previous set',
      loading: SkeletonRows(
        count: 1,
        rowHeight: 36 + MediaQuery.textScalerOf(context).scale(28),
      ),
      retry: () => ref.invalidate(previousSetProvider(filter)),
      builder: (previous) {
        if (previous == null) {
          return RowLink(
            title: 'Previous',
            subtitle: 'No earlier set',
            leading: Icon(
              LucideIcons.history,
              size: 20,
              color: context.colors.muted,
            ),
            showChevron: false,
          );
        }
        final active = input.activeSet;
        final canCopy = !_busy && (!_liveWorkout || !active.completed);
        final row = RowLink(
          title: 'Previous',
          subtitle:
              '${fullDay(previous.day)} · ${measure(previous.value, input.exercise.measurement, style, reps: previous.reps)}',
          leading: Icon(
            canCopy ? LucideIcons.copy : LucideIcons.history,
            size: 20,
            color: context.colors.muted,
          ),
          detail: canCopy ? 'Copy' : null,
          detailStyle: context.type.labelLarge?.copyWith(
            color: context.colors.green,
          ),
          showChevron: false,
          onTap: canCopy ? () => _copyPrevious(active, previous) : null,
        );
        return canCopy ? Tooltip(message: 'Use previous set', child: row) : row;
      },
    );
  }

  void _copyPrevious(_SetInput set, PreviousSet previous) {
    if (_busy || (_liveWorkout && set.completed)) return;
    setState(() {
      if (set.measurement == Measurement.duration) {
        set.first.text = '${previous.value ~/ 60}';
        set.second.text = (previous.value % 60).toString().padLeft(2, '0');
      } else {
        set.first.text = measureValue(
          previous.value,
          set.measurement,
          DurationStyle.seconds,
        );
        if (set.measurement.needsReps) {
          set.second.text = previous.reps?.toString() ?? '';
        }
      }
    });
  }

  bool get _isRepeatDraft => widget.request?.repeatEntries.isNotEmpty ?? false;

  Widget _group(_ExerciseInput input, DurationStyle style) {
    final active = input.activeSet;
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
        const SizedBox(height: Space.md),
        if (input.showsSets || _liveWorkout)
          Row(
            children: [
              Expanded(
                child: Text(
                  'Set ${input.sets.indexOf(active) + 1}',
                  style: context.type.labelLarge,
                ),
              ),
              if (input.sets.length > 1)
                RoundControl(
                  LucideIcons.circleMinus,
                  'Remove set ${input.sets.indexOf(active) + 1}',
                  _busy || (_liveWorkout && active.completed)
                      ? null
                      : () => _removeSet(input, active),
                ),
            ],
          ),
        if (!input.knownNoHistory && !_isRepeatDraft)
          _previousSetContext(input, style),
        const SizedBox(height: Space.md),
        KeyedSubtree(
          key: ObjectKey(active),
          child: _valueInput(
            active,
            autofocus:
                _entry == null &&
                input == _selectedGroup &&
                (widget.request?.repeatEntries.isEmpty ?? true),
          ),
        ),
        if (_liveWorkout)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: QuietButton(
              active.completed ? 'Undo complete set' : 'Complete set',
              _busy
                  ? null
                  : active.completed
                  ? () => _activateSet(input, active, unlock: true)
                  : () => _completeSet(input, active),
              icon: active.completed
                  ? LucideIcons.rotateCcw
                  : LucideIcons.check,
            ),
          ),
        const SizedBox(height: Space.md),
        for (final (index, set) in input.sets.indexed)
          if (set != active)
            RowLink(
              key: ObjectKey(set),
              title: 'Set ${index + 1}',
              subtitle: _liveWorkout && set.completed ? 'Completed' : null,
              detail: switch (set.value) {
                final value? => measure(
                  value,
                  set.measurement,
                  style,
                  reps: set.reps,
                ),
                null => 'Incomplete',
              },
              onTap: _busy ? null : () => _activateSet(input, set),
            ),
        if (input.exercise.trackSets || _liveWorkout)
          QuietButton(
            'Add set',
            _busy || input.sets.length >= maxSetsPerEntry
                ? null
                : () => _addSet(input),
            icon: LucideIcons.plus,
          ),
        if (_groups.length > 1) _notes(input),
        const Divider(),
      ],
    );
  }

  Widget _notes(_ExerciseInput input) => input.showNotes
      ? Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.md),
          child: TextFormField(
            controller: input.notes,
            enabled: !_busy,
            minLines: 2,
            maxLines: 5,
            maxLength: maxNotes,
            maxLengthEnforcement: MaxLengthEnforcement.none,
            buildCounter:
                (_, {required currentLength, required isFocused, maxLength}) =>
                    currentLength < maxNotes - 200
                    ? null
                    : Text(
                        '$currentLength/$maxNotes',
                        semanticsLabel:
                            '$currentLength of $maxNotes characters',
                      ),
            validator: (value) => graphemeCount(value ?? '') > maxNotes
                ? 'Keep notes to $maxNotes characters or fewer.'
                : null,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Notes'),
            onChanged: (_) => setState(() {}),
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
    String? subtitle,
    Widget? footer,
    bool Function()? editorDirty,
    bool Function()? editorBusy,
  }) {
    bool isEditorDirty() => editorDirty?.call() ?? false;
    bool isEditorBusy() => editorBusy?.call() ?? false;
    final busy = _busy || isEditorBusy();
    final firstStep =
        _step == _LogStep.chooseExercise &&
        (!_liveWorkout || _groups.isNotEmpty);
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
        subtitle: subtitle,
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
    ref.listen(restTimerEnabledProvider, (_, next) {
      if (next.asData?.value == false) _clearRestTimer();
    });
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
    final repeatEntries =
        widget.request?.repeatEntries ?? const <RepeatEntry>[];
    final repeatSourceDay = widget.request?.repeatSourceDay;
    final repeatExerciseCount = repeatEntries
        .map((repeated) => repeated.exercise.id)
        .toSet()
        .length;
    final repeatSetCount = repeatEntries.fold(
      0,
      (sum, repeated) => sum + repeated.entry.sets.length,
    );
    final skippedArchivedCount = widget.request?.skippedArchivedCount ?? 0;
    final fields = <Widget>[
      if (skippedArchivedCount > 0)
        Padding(
          padding: const EdgeInsets.only(top: Space.md),
          child: Text(
            '$skippedArchivedCount archived entr${skippedArchivedCount == 1 ? 'y was' : 'ies were'} skipped. Unarchive them to include them.',
            style: context.type.bodySmall?.copyWith(
              color: context.colors.muted,
            ),
          ),
        ),
      for (final group in _groups) ...[
        const SizedBox(height: Space.md),
        _group(group, style),
      ],
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
      label: _liveWorkout
          ? 'Finish workout'
          : _entry == null
          ? _groups.every((group) => group.exercise.trackSets)
                ? 'Save $count ${count == 1 ? 'set' : 'sets'}'
                : 'Save activity'
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
    final canUseTimer =
        _liveWorkout &&
        !choosing &&
        ref.watch(restTimerEnabledProvider).value == true;
    return _sheet(
      title: _liveWorkout && !adding
          ? 'Live workout'
          : choosing
          ? 'Choose exercise'
          : repeatSourceDay != null && repeatEntries.isNotEmpty
          ? 'Repeat workout'
          : 'Add entry',
      subtitle: repeatSourceDay != null && repeatEntries.isNotEmpty
          ? 'From ${fullDay(repeatSourceDay)} · '
                '$repeatExerciseCount ${repeatExerciseCount == 1 ? 'exercise' : 'exercises'} · '
                '$repeatSetCount ${repeatSetCount == 1 ? 'set' : 'sets'}'
          : null,
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
                if (canUseTimer) _restStatus(),
                footer,
              ],
            ),
      child: choosing
          ? _ExercisePicker(
              key: ValueKey(_step),
              onSelect: (item) =>
                  _select(item.exercise, knownNoHistory: item.lastDay == null),
              onCreate: _createExercise,
              liveWorkout: _liveWorkout,
              onStartLiveWorkout:
                  !_liveWorkout && widget.request == null && _groups.isEmpty
                  ? _startLiveWorkout
                  : null,
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
  _ExerciseInput(this.exercise, Entry? original, {this.knownNoHistory = false})
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

  _ExerciseInput.repeat(this.exercise, Entry source)
    : notes = TextEditingController(),
      originalNotes = '',
      originalSets = source.sets,
      knownNoHistory = false,
      showNotes = false,
      sets = [
        for (final set in source.sets)
          _SetInput(exercise.measurement, set, preserveId: false),
      ];

  Exercise exercise;
  final TextEditingController notes;
  final String originalNotes;
  final List<RecordedSet>? originalSets;
  final List<_SetInput> sets;
  bool knownNoHistory;
  late _SetInput activeSet = sets.last;
  bool showNotes;

  bool get showsSets => exercise.trackSets || (originalSets?.length ?? 0) > 1;

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
          return set.id != original[i].id ||
              set.value != original[i].value ||
              set.reps != original[i].reps;
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
  _SetInput(this.measurement, RecordedSet? original, {bool preserveId = true})
    : id = preserveId ? original?.id : null,
      first = TextEditingController(
        text: original == null
            ? ''
            : measurement == Measurement.duration
            ? '${original.value ~/ 60}'
            : measureValue(original.value, measurement, DurationStyle.seconds),
      ),
      second = TextEditingController(
        text: original == null
            ? ''
            : measurement == Measurement.duration
            ? (original.value % 60).toString().padLeft(2, '0')
            : original.reps?.toString() ?? '',
      );

  final Measurement measurement;
  final String? id;
  final TextEditingController first, second;
  final firstFocus = FocusNode(), secondFocus = FocusNode();
  bool completed = false;

  bool get _timed => measurement == Measurement.duration;
  int? get _minutes =>
      first.text.trim().isEmpty ? 0 : int.tryParse(first.text, radix: 10);
  int? get _seconds =>
      second.text.trim().isEmpty ? 0 : int.tryParse(second.text, radix: 10);
  int? get reps => measurement.needsReps
      ? int.tryParse(second.text.trim(), radix: 10)
      : null;

  String? get firstError {
    if (!_timed) {
      return exerciseValueError(
        parseExerciseValue(first.text, measurement),
        measurement,
      );
    }
    final minutes = _minutes;
    return minutes == null || minutes < 0 || minutes > maxSetValue ~/ 60
        ? 'Enter valid minutes.'
        : null;
  }

  String? get secondError {
    if (measurement.needsReps) {
      return exerciseValueError(reps, Measurement.repetitions);
    }
    if (!_timed) return null;
    final seconds = _seconds;
    if (seconds == null || seconds < 0 || seconds > 59) return 'Enter 0 to 59.';
    if (first.text.trim().isEmpty && second.text.trim().isEmpty ||
        firstError == null && _minutes! * 60 + seconds > maxSetValue) {
      return 'Enter a valid duration.';
    }
    return null;
  }

  int? get value => firstError != null || secondError != null
      ? null
      : _timed
      ? _minutes! * 60 + _seconds!
      : parseExerciseValue(first.text, measurement);

  void focusInvalid() =>
      (firstError != null ? firstFocus : secondFocus).requestFocus();

  void dispose() {
    first.dispose();
    second.dispose();
    firstFocus.dispose();
    secondFocus.dispose();
  }
}
