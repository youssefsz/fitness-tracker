import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../shared/domain/training.dart';
import '../../shared/widgets/ui.dart';
import 'transfer_codec.dart';

String _encodeExport((BackupData, DateTime, bool) input) =>
    input.$3 ? encodeCsv(input.$1) : encodeBackup(input.$1, input.$2);

class YourDataPage extends ConsumerStatefulWidget {
  const YourDataPage({super.key});

  @override
  ConsumerState<YourDataPage> createState() => _YourDataPageState();
}

class _YourDataPageState extends ConsumerState<YourDataPage> {
  bool _busy = false;
  String? _problem;

  Future<void> _run(
    Future<void> Function() action, {
    required String fallback,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() => _problem = describeError(error, fallback: fallback));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(bool csv) => _run(
    () async {
      final fileSystem = ref.read(filesProvider);
      final clock = ref.read(nowProvider)();
      final snapshot = await ref.read(repositoryProvider).snapshot();
      final content = await compute(_encodeExport, (snapshot, clock, csv));
      if (!mounted) return;
      final anchor = context.findRenderObject() as RenderBox?;
      final rect = anchor == null || !anchor.hasSize
          ? Offset.zero & const Size(1, 1)
          : anchor.localToGlobal(anchor.size.center(Offset.zero)) &
                const Size(1, 1);
      final date = CalendarDay.fromDate(clock).iso;
      await fileSystem.share(
        'fitness-tracker-${csv ? 'sets' : 'backup'}-$date.${csv ? 'csv' : 'json'}',
        content,
        rect,
        csv: csv,
      );
    },
    fallback:
        'Couldn’t prepare the export. Check available storage and try again.',
  );

  Future<void> _recovery() => _run(() async {
    final files = await ref.read(filesProvider).recoveryFiles();
    if (!mounted) return;
    if (files.isEmpty) {
      announce(context, 'No recovery backups on this device.');
      return;
    }
    final file = await chooseOption<String>(context, 'Recovery backups', [
      for (final name in files)
        (
          value: name,
          label:
              'Before restore · ${name.length >= 25 ? name.substring(15, 25) : name}',
          subtitle: name,
        ),
    ]);
    if (mounted && file != null) context.push('/transfer/backup', extra: file);
  }, fallback: 'Couldn’t read recovery backups.');

  Future<void> _reset({required bool allData}) async {
    if (_busy) return;
    final label = allData ? 'Reset all app data' : 'Delete all exercises';
    final confirmed = await confirmAction(
      context,
      title: '$label?',
      message: allData
          ? 'This permanently deletes your exercises, workout history, goals, profile, weigh-ins, and local backup copies. Settings return to their defaults.'
          : 'This permanently deletes all exercises, workout history, and exercise goals. Your profile, weigh-ins, and settings are kept.',
      label: label,
      destructive: true,
    );
    if (!mounted || !confirmed) return;
    await _run(() async {
      final repo = ref.read(repositoryProvider);
      if (allData) {
        final files = ref.read(filesProvider);
        // Let any in-flight photo recovery finish before clearing the profile.
        await ref.read(recoverProfilePhotoProvider.future).onError((_, _) {});
        await repo.resetAllData();
        try {
          await files.clearLocalCopies();
        } catch (_) {
          throw const TrackerException(
            'Your records were reset, but some local copies could not be removed. Try Reset all app data again.',
          );
        }
      } else {
        await repo.deleteAllExercises();
      }
      if (mounted) {
        announce(
          context,
          allData ? 'App data reset.' : 'All exercises deleted.',
        );
      }
    }, fallback: 'Couldn’t reset your data. Please try again.');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: secondaryBar(context),
    body: ScreenScroll(
      children: [
        const ScreenHeading('Your data', top: 0),
        Text(
          'Your records are stored on this device.',
          style: context.type.bodyMedium,
        ),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        FormProblem(_problem),
        const SizedBox(height: Space.xl),
        const SectionTitle('Backup and restore'),
        RowLink(
          title: 'Export backup',
          subtitle: 'Save workouts, profile details, and weigh-ins as JSON. Your photo stays on this device.',
          leading: const Icon(LucideIcons.upload, size: 20),
          onTap: _busy ? null : () => _export(false),
        ),
        RowLink(
          title: 'Import backup',
          subtitle: 'Merge or restore from a JSON file',
          leading: const Icon(LucideIcons.download, size: 20),
          onTap: _busy ? null : () => context.push('/transfer/backup'),
        ),
        RowLink(
          title: 'Recovery backups',
          subtitle: 'Open a copy saved before a restore',
          leading: const Icon(LucideIcons.history, size: 20),
          onTap: _busy ? null : _recovery,
          separator: false,
        ),
        const SizedBox(height: Space.xl),
        const SectionTitle('Workout import and export'),
        RowLink(
          title: 'Export CSV',
          subtitle: 'Open workout sets in a spreadsheet',
          leading: const Icon(LucideIcons.table, size: 20),
          onTap: _busy ? null : () => _export(true),
        ),
        RowLink(
          title: 'Import from AI chat',
          subtitle: 'Bring in sets using a prompt and JSON',
          leading: const Icon(LucideIcons.messageSquare, size: 20),
          onTap: _busy ? null : () => context.push('/transfer/activity'),
          separator: false,
        ),
        const SizedBox(height: Space.xl),
        const SectionTitle('Reset data'),
        RowLink(
          title: 'Delete all exercises',
          subtitle: 'Remove exercises, workout history, and exercise goals',
          leading: Icon(
            LucideIcons.trash2,
            size: 20,
            color: context.colors.danger,
          ),
          onTap: _busy ? null : () => _reset(allData: false),
        ),
        RowLink(
          title: 'Reset all app data',
          subtitle: 'Remove local app data and restore default settings',
          leading: Icon(
            LucideIcons.trash2,
            size: 20,
            color: context.colors.danger,
          ),
          onTap: _busy ? null : () => _reset(allData: true),
          separator: false,
        ),
      ],
    ),
  );
}
