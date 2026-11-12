import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/branding.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../shared/domain/training.dart';
import '../../shared/widgets/ui.dart';
import '../data_transfer/transfer_codec.dart';

String _encodeExport((BackupData, DateTime, bool) input) =>
    input.$3 ? encodeCsv(input.$1) : encodeBackup(input.$1, input.$2);

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
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

  Future<void> _save(Preferences preferences) => _run(
    () => ref.read(repositoryProvider).savePreferences(preferences),
    fallback: 'Couldn’t save this preference.',
  );

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

  Future<void> _about() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          Image.asset(
            Branding.mark,
            width: 36,
            height: 36,
            color: context.colors.ink,
            excludeFromSemantics: true,
          ),
          const SizedBox(width: 8),
          const Flexible(child: Text(Branding.name)),
        ],
      ),
      content: const Text(
        'A personal exercise log for repetitions and timed sets. Your records are stored on this device. Export a backup to move them to another device.',
      ),
      actions: [
        TextButton(
          onPressed: () => showLicensePage(
            context: context,
            applicationName: Branding.name,
            applicationVersion: Branding.version,
          ),
          child: const Text('Licenses'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: secondaryBar(context),
    body: ScreenScroll(
      children: [
        const ScreenHeading('Settings', top: 0),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        AsyncPanel(
          ref.watch(preferencesProvider),
          retry: () => ref.invalidate(preferencesProvider),
          builder: (prefs) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle('Preferences'),
              const SizedBox(height: 6),
              RowLink(
                title: 'Appearance',
                detail: _appearance(prefs.appearance),
                onTap: _busy
                    ? null
                    : () async {
                        final value = await chooseOption<Appearance>(
                          context,
                          'Appearance',
                          [
                            for (final a in Appearance.values)
                              (value: a, label: _appearance(a), subtitle: null),
                          ],
                          selected: prefs.appearance,
                        );
                        if (mounted &&
                            value != null &&
                            value != prefs.appearance) {
                          await _save((
                            appearance: value,
                            duration: prefs.duration,
                            haptics: prefs.haptics,
                          ));
                        }
                      },
              ),
              RowLink(
                title: 'Duration display',
                detail: prefs.duration == DurationStyle.clock
                    ? 'Min:sec'
                    : 'Seconds',
                onTap: _busy
                    ? null
                    : () async {
                        final style = await chooseOption<DurationStyle>(
                          context,
                          'Duration display',
                          const [
                            (
                              value: DurationStyle.clock,
                              label: 'Minutes and seconds',
                              subtitle: '1:30',
                            ),
                            (
                              value: DurationStyle.seconds,
                              label: 'Seconds',
                              subtitle: '90 sec',
                            ),
                          ],
                          selected: prefs.duration,
                        );
                        if (mounted &&
                            style != null &&
                            style != prefs.duration) {
                          await _save((
                            appearance: prefs.appearance,
                            duration: style,
                            haptics: prefs.haptics,
                          ));
                        }
                      },
              ),
              SwitchListTile.adaptive(
                value: prefs.haptics,
                contentPadding: EdgeInsets.zero,
                title: Text('Haptics', style: context.type.titleSmall),
                subtitle: Text(
                  'Feedback for selections and saves',
                  style: context.type.bodySmall,
                ),
                onChanged: _busy
                    ? null
                    : (value) => _save((
                        appearance: prefs.appearance,
                        duration: prefs.duration,
                        haptics: value,
                      )),
              ),
              const Divider(),
              RowLink(
                title: 'Manage exercises',
                subtitle: 'Create, rename, archive, or restore',
                onTap: () => context.push('/exercises'),
              ),
              const SizedBox(height: 26),
              const SectionTitle('Your data'),
              const SizedBox(height: 6),
              RowLink(
                title: 'Export backup',
                subtitle: 'Save everything as a restorable JSON file',
                icon: LucideIcons.share,
                onTap: _busy ? null : () => _export(false),
              ),
              RowLink(
                title: 'Export CSV',
                subtitle: 'Open individual sets in a spreadsheet',
                icon: LucideIcons.share,
                onTap: _busy ? null : () => _export(true),
              ),
              RowLink(
                title: 'Import backup',
                subtitle: 'Merge or restore from a saved backup',
                onTap: _busy ? null : () => context.push('/transfer/backup'),
              ),
              RowLink(
                title: 'Import from AI chat',
                subtitle: 'Bring in sets using a copyable prompt and JSON',
                onTap: _busy ? null : () => context.push('/transfer/activity'),
              ),
              RowLink(
                title: 'Recovery backups',
                subtitle: 'Open a copy saved before a restore',
                onTap: _busy ? null : _recovery,
              ),
              FormProblem(_problem),
              const SizedBox(height: 10),
              Text(
                'Your records are stored on this device. Keep a backup somewhere safe.',
                style: context.type.bodySmall,
              ),
              const SizedBox(height: 26),
              const SectionTitle('About'),
              RowLink(title: 'About this app', onTap: _about),
              const RowLink(
                title: 'Version',
                detail: Branding.version,
                separator: false,
              ),
            ],
          ),
        ),
      ],
    ),
  );

  String _appearance(Appearance value) => switch (value) {
    Appearance.system => 'System',
    Appearance.light => 'Light',
    Appearance.dark => 'Dark',
  };
}
