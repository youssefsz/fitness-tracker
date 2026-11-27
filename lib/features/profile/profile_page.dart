import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/branding.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../shared/domain/body_metrics.dart';
import '../../shared/domain/training.dart';
import '../../shared/widgets/collapsing_page.dart';
import '../../shared/widgets/ui.dart';
import '../update/android_update_host.dart';
import 'appearance_picker.dart';
import 'email_support.dart';
import 'measurement_input.dart';
import 'profile_avatar.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const latestFilter = (limit: 1, since: null);
    final profile = ref.watch(profileProvider);
    final weights = weighInsProvider(latestFilter);
    final latest = ref.watch(weights);
    final value = profile.value;
    return CollapsingPage(
      title: 'Profile',
      avatar: SkeletonCrossfade(
        placeholder: const Skeleton(width: 74, height: 74, circular: true),
        child: value == null && !profile.hasError
            ? null
            : ProfileAvatar(
                photo: value?.photo,
                preset: value?.avatarPreset ?? AvatarPreset.anonymous,
              ),
      ),
      body: (controller, titleKey, avatarSlot) => ScreenScroll(
        controller: controller,
        children: [
          ScreenHeading('Profile', top: 0, titleKey: titleKey),
          _ProfileIdentity(profile: profile, avatarSlot: avatarSlot),
          const SizedBox(height: Space.xl),
          const SectionTitle('Body measurements'),
          const SizedBox(height: Space.sm),
          _Measurements(profile: profile, weighIns: latest),
          if (latest.hasError && !latest.hasValue)
            QuietButton('Retry weigh-ins', () => ref.invalidate(weights)),
          const SizedBox(height: Space.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              onPressed: () => context.push('/profile/weigh-in'),
              icon: const Icon(LucideIcons.plus, size: 18),
              label: const Text('Log weight'),
            ),
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
}

class _ProfileIdentity extends ConsumerWidget {
  const _ProfileIdentity({required this.profile, required this.avatarSlot});
  final AsyncValue<LocalProfile> profile;
  final Widget avatarSlot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nameStyle = context.type.titleLarge;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            avatarSlot,
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: AsyncPanel(
                      profile,
                      loadingLabel: 'Loading profile',
                      loading: SkeletonText(width: 100, style: nameStyle),
                      retry: () => ref.invalidate(profileProvider),
                      builder: (value) => Text(
                        value.details.displayName ?? 'You',
                        style: nameStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
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
      ],
    );
  }
}

class _Measurements extends StatelessWidget {
  const _Measurements({required this.profile, required this.weighIns});
  final AsyncValue<LocalProfile> profile;
  final AsyncValue<List<WeighIn>> weighIns;

  @override
  Widget build(BuildContext context) {
    final details = profile.value?.details;
    final height = details?.heightMillimeters;
    final latest = weighIns.value?.firstOrNull;
    final heightValue = _Measurement(
      label: 'Height',
      value: switch (details) {
        null => profile.hasError ? 'Unavailable' : null,
        _ =>
          height == null
              ? 'Add height'
              : heightText(context, height, details.heightUnit),
      },
      onTap: () => context.push('/profile/edit'),
    );
    final weightValue = _Measurement(
      label: 'Body weight',
      value: switch (latest) {
        null when weighIns.hasValue => 'No weigh-ins yet',
        null when weighIns.hasError => 'Unavailable',
        null => null,
        _ when details != null => weightText(
          context,
          latest.grams,
          details.weightUnit,
        ),
        _ => profile.hasError ? 'Unavailable' : null,
      },
      date: latest == null ? null : fullDay(latest.day),
      reserveDate: true,
      onTap: () => context.push('/profile/weight'),
    );
    return LayoutBuilder(
      builder: (context, limits) {
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
    );
  }
}

class _Measurement extends StatelessWidget {
  const _Measurement({
    required this.label,
    required this.value,
    required this.onTap,
    this.date,
    this.reserveDate = false,
  });

  final String label;
  final String? value, date;
  final bool reserveDate;
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
            SizedBox(
              width: double.infinity,
              child: SkeletonCrossfade(
                loadingLabel: 'Loading $label',
                placeholder: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonText(width: 82, style: context.type.titleMedium),
                    if (reserveDate) ...[
                      const SizedBox(height: Space.xs),
                      SkeletonText(width: 65, style: context.type.bodySmall),
                    ],
                  ],
                ),
                child: value == null
                    ? null
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(value!, style: context.type.titleMedium),
                          if (reserveDate) ...[
                            const SizedBox(height: Space.xs),
                            Semantics(
                              excludeSemantics: date == null,
                              child: Text(
                                date ?? ' ',
                                style: context.type.bodySmall,
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
            ),
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
        overviewExerciseOrder: prefs.overviewExerciseOrder,
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
        overviewExerciseOrder: prefs.overviewExerciseOrder,
      ));
    }
  }

  Future<void> _restTimer(bool enabled) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _problem = null;
    });
    try {
      await ref.read(repositoryProvider).saveRestTimerEnabled(enabled);
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

  @override
  Widget build(BuildContext context) => AsyncPanel(
    ref.watch(preferencesProvider),
    loading: const SkeletonRows(rowHeight: 50),
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
                  overviewExerciseOrder: prefs.overviewExerciseOrder,
                )),
        ),
        AsyncPanel<bool>(
          ref.watch(restTimerEnabledProvider),
          loadingLabel: 'Loading rest timer preference',
          loading: const SkeletonRows(count: 1, rowHeight: 50),
          retry: () => ref.invalidate(restTimerEnabledProvider),
          builder: (enabled) => SwitchRow(
            value: enabled,
            title: 'Rest timer',
            subtitle: 'Show in live workouts',
            onChanged: _saving ? null : _restTimer,
          ),
        ),
        FormProblem(_problem),
      ],
    ),
  );
}

class _AboutFooter extends ConsumerWidget {
  const _AboutFooter();

  Future<void> _openPrivacyPolicy(BuildContext context) async {
    final uri = Uri.https('fitness-tracker.dhibi.tn', '/privacy/');
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } on PlatformException {
      // Use the same feedback if the platform cannot open the browser.
    }
    if (context.mounted) announce(context, 'Couldn’t open the privacy policy.');
  }

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
          SkeletonCrossfade(
            placeholder: SkeletonText(width: 94, style: context.type.bodySmall),
            child: !metadata.hasValue && !metadata.hasError
                ? null
                : Text(
                    version ?? 'Version unavailable',
                    style: context.type.bodySmall,
                    textAlign: TextAlign.center,
                  ),
          ),
          const AndroidUpdateCheck(),
          EmailSupportButton(buildInfo: build),
          QuietButton('Privacy Policy', () => _openPrivacyPolicy(context)),
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
