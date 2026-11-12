import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/branding.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../shared/domain/body_metrics.dart';
import '../../shared/domain/training.dart';
import '../../shared/widgets/ui.dart';
import 'appearance_picker.dart';
import 'measurement_input.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: secondaryBar(context),
    body: ScreenScroll(
      children: [
        const ScreenHeading('Profile', top: 0),
        AsyncPanel(
          ref.watch(profileProvider),
          retry: () => ref.invalidate(profileProvider),
          builder: (profile) => _ProfileSummary(profile: profile),
        ),
        const SizedBox(height: Space.xl),
        const _Preferences(),
        const SizedBox(height: Space.lg),
        RowLink(
          title: 'Manage exercises',
          leading: const Icon(LucideIcons.dumbbell, size: 20),
          onTap: () => context.push('/exercises'),
        ),
        RowLink(
          title: 'Your data',
          leading: const Icon(LucideIcons.database, size: 20),
          onTap: () => context.push('/profile/data'),
        ),
        const _AboutFooter(),
      ],
    ),
  );
}

class _ProfileSummary extends ConsumerWidget {
  const _ProfileSummary({required this.profile});

  final LocalProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = profile.details;
    final height = details.heightMillimeters;
    const latestFilter = (limit: 1, since: null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ProfileAvatar(photo: profile.photo, preset: profile.avatarPreset),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    details.displayName ?? 'You',
                    style: context.type.titleLarge,
                  ),
                  QuietButton(
                    'Edit profile',
                    () => context.push('/profile/edit'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.xl),
        const SectionTitle('Body measurements'),
        const SizedBox(height: Space.sm),
        AsyncPanel(
          ref.watch(weighInsProvider(latestFilter)),
          retry: () => ref.invalidate(weighInsProvider(latestFilter)),
          builder: (records) {
            final latest = records.firstOrNull;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, limits) {
                    final heightValue = _Measurement(
                      label: 'Height',
                      value: height == null
                          ? 'Add height'
                          : heightText(context, height, details.heightUnit),
                      onTap: () => context.push('/profile/edit'),
                    );
                    final weightValue = _Measurement(
                      label: 'Body weight',
                      value: latest == null
                          ? 'No weigh-ins yet'
                          : weightText(
                              context,
                              latest.grams,
                              details.weightUnit,
                            ),
                      date: latest == null ? null : fullDay(latest.day),
                      onTap: () => context.push('/profile/weight'),
                    );
                    final scale = MediaQuery.textScalerOf(context).scale(1);
                    if (limits.maxWidth / scale < 290) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [heightValue, const Divider(), weightValue],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: heightValue),
                        const SizedBox(width: Space.lg),
                        Expanded(child: weightValue),
                      ],
                    );
                  },
                ),
                const SizedBox(height: Space.sm),
                FilledButton.icon(
                  onPressed: () => context.push('/profile/weigh-in'),
                  icon: const Icon(LucideIcons.plus, size: 18),
                  label: const Text('Log weight'),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Measurement extends StatelessWidget {
  const _Measurement({
    required this.label,
    required this.value,
    required this.onTap,
    this.date,
  });

  final String label, value;
  final String? date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(child: Text(label, style: context.type.bodyMedium)),
                const SizedBox(width: Space.xs),
                Icon(
                  LucideIcons.chevronRight,
                  size: 15,
                  color: context.colors.muted,
                ),
              ],
            ),
            const SizedBox(height: Space.xs),
            Text(value, style: context.type.titleMedium),
            if (date case final text?) ...[
              const SizedBox(height: Space.xs),
              Text(text, style: context.type.bodySmall),
            ],
          ],
        ),
      ),
    ),
  );
}

class _Preferences extends ConsumerStatefulWidget {
  const _Preferences();

  @override
  ConsumerState<_Preferences> createState() => _PreferencesState();
}

class _PreferencesState extends ConsumerState<_Preferences> {
  bool _saving = false;
  String? _problem;

  String _durationExample(DurationStyle style) =>
      measure(90, Measurement.duration, style);

  Future<void> _save(Preferences preferences) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _problem = null;
    });
    try {
      await ref.read(repositoryProvider).savePreferences(preferences);
    } catch (error) {
      if (mounted) {
        setState(
          () => _problem = describeError(
            error,
            fallback: 'Couldn’t save this preference.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _appearance(Preferences prefs) async {
    final selected = await pickAppearance(context, prefs.appearance);
    if (mounted && selected != null && selected != prefs.appearance) {
      await _save((
        appearance: selected,
        duration: prefs.duration,
        haptics: prefs.haptics,
      ));
    }
  }

  Future<void> _duration(Preferences prefs) async {
    final selected = await chooseOption<DurationStyle>(
      context,
      'Duration display',
      [
        for (final value in DurationStyle.values)
          (
            value: value,
            label: value == DurationStyle.clock
                ? 'Minutes and seconds'
                : 'Seconds',
            subtitle: _durationExample(value),
          ),
      ],
      selected: prefs.duration,
    );
    if (mounted && selected != null && selected != prefs.duration) {
      await _save((
        appearance: prefs.appearance,
        duration: selected,
        haptics: prefs.haptics,
      ));
    }
  }

  @override
  Widget build(BuildContext context) => AsyncPanel(
    ref.watch(preferencesProvider),
    retry: () => ref.invalidate(preferencesProvider),
    builder: (prefs) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('Preferences'),
        const SizedBox(height: Space.xs),
        RowLink(
          title: 'Appearance',
          detail: appearanceLabel(prefs.appearance),
          onTap: _saving ? null : () => _appearance(prefs),
        ),
        RowLink(
          title: 'Duration display',
          detail: _durationExample(prefs.duration),
          onTap: _saving ? null : () => _duration(prefs),
        ),
        SwitchRow(
          value: prefs.haptics,
          title: 'Haptics',
          onChanged: _saving
              ? null
              : (value) => _save((
                  appearance: prefs.appearance,
                  duration: prefs.duration,
                  haptics: value,
                )),
        ),
        FormProblem(_problem),
      ],
    ),
  );
}

class _AboutFooter extends ConsumerWidget {
  const _AboutFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metadata = ref.watch(appBuildProvider);
    final build = metadata.value;
    final version = build == null || build.version.isEmpty
        ? null
        : build.number.isEmpty
        ? 'Version ${build.version}'
        : 'Version ${build.version} (${build.number})';
    return Padding(
      padding: const EdgeInsets.only(top: Space.xxl),
      child: Column(
        children: [
          Image.asset(
            Branding.mark,
            width: 42,
            height: 42,
            color: context.colors.ink,
            excludeFromSemantics: true,
          ),
          const SizedBox(height: Space.sm),
          Text(Branding.name, style: context.type.titleSmall),
          const SizedBox(height: Space.xs),
          if (version != null || metadata.hasError)
            Text(
              version ?? 'Version unavailable',
              style: context.type.bodySmall,
              textAlign: TextAlign.center,
            ),
          QuietButton(
            'Licenses',
            () => showLicensePage(
              context: context,
              applicationName: Branding.name,
              applicationVersion: version,
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    required this.photo,
    required this.preset,
    this.size = 74,
    super.key,
  });

  final Uint8List? photo;
  final AvatarPreset preset;
  final double size;

  @override
  Widget build(BuildContext context) {
    final presetImage = Image.asset(
      'assets/avatars/${preset.name}.webp',
      fit: BoxFit.cover,
    );
    return ExcludeSemantics(
      child: ClipOval(
        child: SizedBox.square(
          dimension: size,
          child: photo == null
              ? presetImage
              : Image.memory(
                  photo!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => presetImage,
                ),
        ),
      ),
    );
  }
}
