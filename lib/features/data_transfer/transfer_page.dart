import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../shared/domain/training.dart';
import '../../shared/widgets/exercise_icon.dart';
import '../../shared/widgets/ui.dart';
import 'import_plan.dart';
import 'transfer_codec.dart';

BackupData _parseBackup((String, CalendarDay) input) =>
    decodeBackup(input.$1, input.$2);
ActivityBatch _parseActivity((String, CalendarDay) input) =>
    decodeActivity(input.$1, input.$2);
String _snapshotHash(BackupData snapshot) => backupFingerprint(snapshot);
String _recoveryContent((BackupData, DateTime) input) {
  final text = encodeBackup(input.$1, input.$2);
  decodeBackup(text, CalendarDay.fromDate(input.$2));
  return text;
}

class TransferPage extends ConsumerStatefulWidget {
  const TransferPage({required this.activity, this.recoveryFile, super.key});
  final bool activity;
  final String? recoveryFile;

  @override
  ConsumerState<TransferPage> createState() => _TransferPageState();
}

class _TransferPageState extends ConsumerState<TransferPage> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _previewAnchor = GlobalKey();
  bool _busy = false, _allowRepeat = false, _includeCatalog = false;
  bool _showConflictList = false, _confirming = false;
  int _shownMappings = 15;
  String? _problem,
      _mappingProblem,
      _previewHash,
      _filename,
      _fileText,
      _copyMessage;
  RestoreMode _mode = RestoreMode.merge;
  BackupData? _local, _backup;
  BackupPlan? _backupPlan;
  ActivityBatch? _batch;
  ActivityPlan? _activityPlan;
  Map<String, ExerciseMapping> _mappings = {};

  bool get _hasPreview => _backup != null || _batch != null;

  @override
  void initState() {
    super.initState();
    final recovery = widget.recoveryFile;
    if (recovery != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _readFile(recovery: recovery);
      });
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _clearPreview() {
    _local = _backup = null;
    _backupPlan = null;
    _batch = null;
    _activityPlan = null;
    _previewHash = _problem = _mappingProblem = null;
    _mappings = {};
    _allowRepeat = false;
    _shownMappings = 15;
    _showConflictList = false;
  }

  Future<void> _run(Future<void> Function() job, {String? fallback}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await job();
    } catch (error) {
      if (mounted) {
        setState(
          () => _problem = describeError(
            error,
            fallback: fallback ?? 'Couldn’t finish. Try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _readFile({String? recovery}) => _run(() async {
    final files = ref.read(filesProvider);
    final text = recovery == null
        ? await files.pickJson()
        : await files.readRecovery(recovery);
    if (text == null || !mounted) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _clearPreview();
      _filename = recovery ?? 'Selected JSON file';
      _fileText = text;
      _text.clear();
    });
    await _validateText(text);
  }, fallback: 'Couldn’t read the selected JSON file.');

  Future<void> _validatePaste() {
    FocusScope.of(context).unfocus();
    final text = _fileText ?? _text.text;
    setState(() {
      _clearPreview();
    });
    return _run(() => _validateText(text));
  }

  Future<void> _validateText(String text) async {
    if (text.trim().isEmpty) {
      throw const TrackerException('Paste JSON or choose a JSON file first.');
    }
    final today = ref.read(todayProvider);
    final repo = ref.read(repositoryProvider);
    if (widget.activity) {
      final batch = await compute(_parseActivity, (text, today));
      final current = await repo.snapshot();
      final hash = await compute(_snapshotHash, current);
      if (!mounted) return;
      setState(() {
        _local = current;
        _batch = batch;
        _previewHash = hash;
        _mappings = suggestMappings(batch, current.exercises);
        _replanActivity();
      });
    } else {
      final backup = await compute(_parseBackup, (text, today));
      final current = await repo.snapshot();
      final hash = await compute(_snapshotHash, current);
      if (!mounted) return;
      setState(() {
        _local = current;
        _backup = backup;
        _previewHash = hash;
        _backupPlan = planBackup(current, backup, _mode);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _previewAnchor.currentContext;
      if (mounted && target != null) {
        Scrollable.ensureVisible(
          target,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
        );
      }
    });
  }

  void _replanActivity() {
    try {
      _activityPlan = planActivity(_local!, _batch!, _mappings);
      _mappingProblem = null;
    } on TrackerException catch (error) {
      _activityPlan = null;
      _mappingProblem = error.message;
    }
  }

  Future<void> _mapping(String key, ActivityRecord record) async {
    final candidates = _local!.exercises.where(
      (exercise) => exercise.measurement == record.measurement,
    );
    final selected = switch (_mappings[key]) {
      MapToExercise(:final id) => id,
      CreateMappedExercise() => '',
      null => null,
    };
    final target = await chooseOption<String>(
      context,
      'Map ${record.name}',
      [
        (
          value: '',
          label: 'Create an exercise',
          subtitle: 'Choose a unique name',
        ),
        for (final x in candidates)
          (
            value: x.id,
            label: x.name,
            subtitle: x.archived
                ? 'Archived · stays archived'
                : x.measurement.label,
          ),
      ],
      selected: selected,
      leading: (id, name) => id.isEmpty ? null : ExerciseIcon(name),
    );
    if (!mounted || target == null) return;
    ExerciseMapping mapping;
    if (target.isEmpty) {
      final name = await showDialog<String>(
        context: context,
        builder: (_) => _MappingNameDialog(
          initial: switch (_mappings[key]) {
            CreateMappedExercise(:final name) => name,
            _ => record.name,
          },
        ),
      );
      if (!mounted || name == null) return;
      mapping = CreateMappedExercise(name);
    } else {
      mapping = MapToExercise(target);
    }
    setState(() {
      _mappings[key] = mapping;
      _replanActivity();
      _problem = null;
    });
  }

  Future<void> _copy(String text, String label) async {
    try {
      await ref.read(filesProvider).copy(text);
      if (mounted) {
        if (label == 'Prompt') {
          setState(() => _copyMessage = 'Prompt copied.');
        } else {
          announce(context, '$label copied.');
        }
      }
    } catch (error) {
      if (mounted) {
        announce(
          context,
          describeError(error, fallback: 'Couldn’t copy to the clipboard.'),
        );
      }
    }
  }

  Future<void> _example(CalendarDay today) => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    constraints: BoxConstraints(
      maxWidth: 650,
      maxHeight: MediaQuery.sizeOf(context).height * .78,
    ),
    builder: (sheet) => SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        shrinkWrap: true,
        children: [
          const SectionTitle('Example JSON'),
          const SizedBox(height: 5),
          Text(
            'These are sample values. Use dates and sets you actually recorded.',
            style: context.type.bodySmall,
          ),
          const SizedBox(height: 10),
          SelectableText(
            activityExample(today),
            style: context.type.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: () => _copy(activityExample(today), 'Example'),
            child: const Text('Copy example'),
          ),
        ],
      ),
    ),
  );

  void _checkPreview(BackupData current, String hash) {
    if (backupFingerprint(current) != hash) {
      throw const TrackerException(
        'Your records changed after the preview. Validate the source again.',
      );
    }
  }

  Future<void> _apply() async {
    if (_busy || _confirming) return;
    final mode = _mode;
    if (_backup != null && mode == RestoreMode.replace) {
      _confirming = true;
      try {
        final confirm = await confirmAction(
          context,
          title: 'Replace all local data?',
          message: 'Exercises, entries, goals, and preferences will be replaced. A recovery backup is saved on this device first.',
          label: 'Replace data',
          destructive: true,
        );
        if (!mounted || !confirm) return;
      } finally {
        _confirming = false;
      }
    }
    await _run(() async {
      final repo = ref.read(repositoryProvider);
      final files = ref.read(filesProvider);
      final now = ref.read(nowProvider);
      final hash = _previewHash!;
      if (_batch case final batch?) {
        final mappings = Map<String, ExerciseMapping>.of(_mappings);
        final allowRepeat = _allowRepeat;
        final count = _activityPlan!.write.entries.length;
        await repo.importActivity((current) {
          _checkPreview(current, hash);
          return planActivity(current, batch, mappings).write;
        }, allowRepeat: allowRepeat);
        if (mounted) {
          announce(
            context,
            'Imported $count ${count == 1 ? 'entry' : 'entries'}.',
          );
          Navigator.pop(context);
        }
      } else if (_backup case final backup?) {
        await repo.restore(
          (current) {
            _checkPreview(current, hash);
            return planBackup(current, backup, mode).write;
          },
          recover: mode == RestoreMode.replace
              ? (current) async {
                  final timestamp = now();
                  final text = await compute(_recoveryContent, (
                    current,
                    timestamp,
                  ));
                  await files.saveRecovery(
                    'before-restore-${timestamp.toUtc().toIso8601String().replaceAll(':', '-')}.json',
                    text,
                  );
                }
              : null,
        );
        if (mounted) {
          announce(
            context,
            mode == RestoreMode.merge
                ? 'Backup merged.'
                : 'Backup restored. Recovery copy available in Settings.',
          );
          Navigator.pop(context);
        }
      }
    }, fallback: 'Couldn’t import. Your local records were not changed.');
  }

  Widget _activityPreview() {
    final batch = _batch!;
    final groups = activityGroups(batch).entries.toList();
    final plan = _activityPlan;
    final byId = {for (final x in _local!.exercises) x.id: x};
    final setCount = batch.records.fold(0, (total, r) => total + r.sets.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${batch.records.length} entries · $setCount sets · ${groups.length} exercise mappings',
          style: context.type.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          'Review the exercise for each group. An archived exercise stays archived.',
          style: context.type.bodySmall,
        ),
        const SizedBox(height: 10),
        for (final group in groups.take(_shownMappings))
          RowLink(
            title: group.value.name,
            subtitle:
                '${group.value.measurement.label} · ${switch (_mappings[group.key]) {
                  CreateMappedExercise(:final name) => 'Create "$name"',
                  MapToExercise(:final id) => 'Use "${byId[id]?.name ?? id}"${byId[id]?.archived == true ? ' (archived)' : ''}',
                  null => 'Choose a mapping',
                }}',
            onTap: _busy ? null : () => _mapping(group.key, group.value),
          ),
        if (groups.length > _shownMappings)
          QuietButton(
            'Show more mappings',
            () => setState(() => _shownMappings += 15),
          ),
        if (_local!.receipts.containsKey(batch.fingerprint)) ...[
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _allowRepeat,
            contentPadding: EdgeInsets.zero,
            title: const Text('Import again'),
            subtitle: const Text(
              'This exact batch has already been imported. Selecting this adds another copy.',
            ),
            onChanged: _busy
                ? null
                : (value) => setState(() => _allowRepeat = value ?? false),
          ),
        ],
        if (plan != null && plan.possibleDuplicates > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${plan.possibleDuplicates} possible matches with existing activity. These entries will be kept if you confirm.',
              style: context.type.bodySmall,
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'First ${batch.records.length < 3 ? batch.records.length : 3} entries',
          style: context.type.titleSmall,
        ),
        for (final record in batch.records.take(3))
          RowLink(
            title: '${record.name} · ${fullDay(record.day)}',
            subtitle:
                '${record.sets.take(8).join(' · ')}${record.sets.length > 8 ? ' …' : ''} ${record.measurement.unit}',
          ),
        FormProblem(_mappingProblem),
      ],
    );
  }

  Widget _backupPreview() {
    final plan = _backupPlan!;
    final data = plan.write.data;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RadioGroup<RestoreMode>(
          groupValue: _mode,
          onChanged: (mode) {
            if (mode == null || _busy) return;
            try {
              final newPlan = planBackup(_local!, _backup!, mode);
              setState(() {
                _mode = mode;
                _backupPlan = newPlan;
                _problem = null;
              });
            } catch (error) {
              setState(() => _problem = describeError(error));
            }
          },
          child: Column(
            children: [
              RadioListTile<RestoreMode>(
                value: RestoreMode.merge,
                enabled: !_busy,
                contentPadding: EdgeInsets.zero,
                title: const Text('Merge with local data'),
                subtitle: const Text(
                  'Keep local preferences and keep this device’s copy of conflicts.',
                ),
              ),
              const Divider(),
              RadioListTile<RestoreMode>(
                value: RestoreMode.replace,
                enabled: !_busy,
                contentPadding: EdgeInsets.zero,
                title: const Text('Replace all data'),
                subtitle: const Text(
                  'Restore this backup after saving a local recovery copy.',
                ),
              ),
              const Divider(),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${_mode == RestoreMode.merge ? 'Add' : 'Restore'} ${data.exercises.length} exercises, '
          '${data.entries.length} entries and ${data.goals.length} goals.',
          style: context.type.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          '${plan.duplicates} already present · ${plan.conflicts.length} conflicts · '
          '${plan.possibleDuplicates} possible duplicate entries · 0 invalid records',
          style: context.type.bodySmall,
        ),
        if (plan.possibleDuplicates > 0)
          Text(
            'Similar entries with different IDs will be kept.',
            style: context.type.bodySmall,
          ),
        if (plan.conflicts.isNotEmpty) ...[
          QuietButton(
            _showConflictList ? 'Hide conflicts' : 'Review conflicts',
            () => setState(() => _showConflictList = !_showConflictList),
          ),
          if (_showConflictList)
            SizedBox(
              height: 180,
              child: ListView.separated(
                primary: false,
                itemCount: plan.conflicts.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(plan.conflicts[i], style: context.type.bodySmall),
                ),
              ),
            ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayProvider);
    final preview = _hasPreview;
    final canImport =
        preview &&
        (!widget.activity ||
            (_activityPlan != null &&
                (!_activityPlan!.repeated || _allowRepeat)));

    return ProtectDraft<void>(
      dirty: false,
      busy: _busy,
      child: Scaffold(
        appBar: secondaryBar(context),
        body: ScreenScroll(
          controller: _scroll,
          children: [
            ScreenHeading(
              widget.activity ? 'Import from AI chat' : 'Import backup',
              top: 0,
              subtitle: widget.activity
                  ? 'Bring in records you already logged in a chat.'
                  : 'Restore a backup saved as JSON.',
            ),
            if (widget.activity) ...[
              Text(
                'Copy the prompt into your chat. Paste the JSON it returns here, or open it as a file. The app reads the file on this device.',
                style: context.type.bodyMedium,
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _includeCatalog,
                contentPadding: EdgeInsets.zero,
                title: const Text('Include exercise names in prompt'),
                subtitle: const Text('Shares names and units only.'),
                onChanged: _busy
                    ? null
                    : (value) =>
                          setState(() => _includeCatalog = value ?? false),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _copy(
                            aiPrompt(
                              ref.read(nowProvider)(),
                              catalog: _includeCatalog
                                  ? (ref.read(catalogProvider).value ?? [])
                                        .where((r) => !r.exercise.archived)
                                        .map((r) => r.exercise)
                                        .toList()
                                  : const [],
                            ),
                            'Prompt',
                          ),
                    child: const Text('Copy AI prompt'),
                  ),
                  QuietButton(
                    'View example',
                    _busy ? null : () => _example(today),
                  ),
                ],
              ),
              if (_copyMessage != null)
                Semantics(
                  liveRegion: true,
                  child: Text(_copyMessage!, style: context.type.bodySmall),
                ),
              const SizedBox(height: 18),
            ],
            if (_filename != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_filename!, style: context.type.bodySmall),
              ),
            TextField(
              controller: _text,
              enabled: !_busy,
              minLines: 4,
              maxLines: 7,
              keyboardType: TextInputType.multiline,
              autocorrect: false,
              enableSuggestions: false,
              style: context.type.bodySmall?.copyWith(fontFamily: 'monospace'),
              decoration: const InputDecoration(
                labelText: 'Paste JSON',
                alignLabelWithHint: true,
              ),
              onChanged: (_) => setState(() {
                _clearPreview();
                _filename = _fileText = null;
              }),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                QuietButton(
                  'Open JSON file',
                  _busy ? null : _readFile,
                  icon: LucideIcons.folderOpen,
                ),
              ],
            ),
            if (preview) ...[
              const SizedBox(height: 24),
              SectionTitle('Import preview', key: _previewAnchor),
              const SizedBox(height: 10),
              if (widget.activity) _activityPreview() else _backupPreview(),
            ],
            FormProblem(_problem),
          ],
        ),
        bottomNavigationBar: KeyboardFooter(
          child: ActionFooter(
            label: preview
                ? (widget.activity
                      ? 'Confirm import'
                      : _mode == RestoreMode.merge
                      ? 'Merge backup'
                      : 'Restore backup')
                : 'Validate and preview',
            busy: _busy,
            onPressed: preview ? (canImport ? _apply : null) : _validatePaste,
            secondary: preview && (_text.text.isNotEmpty || _fileText != null)
                ? QuietButton('Validate again', _busy ? null : _validatePaste)
                : null,
          ),
        ),
      ),
    );
  }
}

class _MappingNameDialog extends StatefulWidget {
  const _MappingNameDialog({required this.initial});
  final String initial;

  @override
  State<_MappingNameDialog> createState() => _MappingNameDialogState();
}

class _MappingNameDialogState extends State<_MappingNameDialog> {
  late final _name = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New exercise name'),
    content: TextField(
      controller: _name,
      autofocus: true,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(labelText: 'Name', errorText: _error),
      onChanged: (_) => setState(() => _error = null),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () {
          if (exerciseNameError(_name.text) case final error?) {
            setState(() => _error = error);
          } else {
            Navigator.pop(context, _name.text.trim());
          }
        },
        child: const Text('Use name'),
      ),
    ],
  );
}
