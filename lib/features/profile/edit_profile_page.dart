import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../shared/domain/body_metrics.dart';
import '../../shared/widgets/ui.dart';
import 'measurement_input.dart';
import 'profile_page.dart';

class EditProfilePage extends ConsumerWidget {
  const EditProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(profileProvider);
    final profile = result.value;
    if (profile != null) return _ProfileEditor(profile: profile);
    return FormLayout(
      title: 'Edit profile',
      children: [
        AsyncPanel(
          result,
          retry: () => ref.invalidate(profileProvider),
          builder: (_) => const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _ProfileEditor extends ConsumerStatefulWidget {
  const _ProfileEditor({required this.profile});

  final LocalProfile profile;

  @override
  ConsumerState<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends ConsumerState<_ProfileEditor> {
  final _form = GlobalKey<FormState>();
  final _heightField = GlobalKey<FormFieldState<int>>();
  final _name = TextEditingController();
  final _height = TextEditingController();
  final _inches = TextEditingController();
  late final ProfileDetails _initial = widget.profile.details;
  late HeightUnit _heightUnit = _initial.heightUnit;
  late WeightUnit _weightUnit = _initial.weightUnit;
  bool _initialized = false, _saving = false, _photoBusy = false;
  String? _saveProblem, _photoProblem;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _name.text = _initial.displayName ?? '';
    _fillHeight(_initial.heightMillimeters);
  }

  @override
  void dispose() {
    _name.dispose();
    _height.dispose();
    _inches.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _name.text.trim() != (_initial.displayName ?? '') ||
      _heightValue != _initial.heightMillimeters ||
      (!_heightEmpty && _heightValue == null) ||
      _heightUnit != _initial.heightUnit ||
      _weightUnit != _initial.weightUnit;

  bool get _heightEmpty =>
      _height.text.trim().isEmpty && _inches.text.trim().isEmpty;

  int? get _heightValue {
    if (_heightUnit == HeightUnit.cm) {
      return parseMeasurement(_height.text, 10, decimals: 1);
    }
    if (_heightEmpty) return null;
    final feet = _height.text.trim().isEmpty
        ? 0
        : int.tryParse(_height.text.trim(), radix: 10);
    final inches = _inches.text.trim().isEmpty
        ? 0
        : parseMeasurement(_inches.text, 100, decimals: 2);
    if (feet == null ||
        feet < 0 ||
        feet > 9 ||
        inches == null ||
        inches >= inchesPerFoot * 100) {
      return null;
    }
    final hundredths = feet * inchesPerFoot * 100 + inches;
    if (hundredths >
        (maxHeightMillimeters * 100 / millimetersPerInch).round()) {
      return null;
    }
    return (hundredths * millimetersPerInch / 100).round();
  }

  String? _heightError() {
    if (_heightEmpty) return null;
    final height = _heightValue;
    if (height != null && height >= 1 && height <= maxHeightMillimeters) {
      return null;
    }
    return _heightUnit == HeightUnit.cm
        ? 'Enter 0.1 to 300 cm, with up to one decimal place.'
        : 'Enter whole feet and 0 to 11.99 inches, up to 9 ft 10.11 in total.';
  }

  void _fillHeight(int? millimeters) {
    if (millimeters == null) {
      _height.clear();
      _inches.clear();
    } else if (_heightUnit == HeightUnit.cm) {
      _height.text = measurementText(context, millimeters / 10, decimals: 1);
      _inches.clear();
    } else {
      final height = heightInFeetAndInches(millimeters);
      _height.text = '${height.feet}';
      _inches.text = measurementText(context, height.inches, decimals: 2);
    }
  }

  Future<void> _chooseHeightUnit() async {
    FocusScope.of(context).unfocus();
    final unit = await chooseOption<HeightUnit>(context, 'Height unit', [
      for (final unit in HeightUnit.values)
        (value: unit, label: unit.label, subtitle: unit.symbol),
    ], selected: _heightUnit);
    if (!mounted || unit == null || unit == _heightUnit) return;
    if (!_heightField.currentState!.validate()) return;
    final millimeters = _heightValue;
    setState(() {
      _heightUnit = unit;
      _fillHeight(millimeters);
    });
  }

  Widget _heightInputs(bool busy) => FormField<int>(
    key: _heightField,
    validator: (_) => _heightError(),
    builder: (field) {
      Widget input(
        String label,
        TextEditingController controller, {
        bool decimal = true,
        bool next = false,
        String? suffix,
      }) => TextField(
        key: ValueKey(label),
        controller: controller,
        enabled: !busy,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        textInputAction: next ? TextInputAction.next : TextInputAction.done,
        decoration: InputDecoration(labelText: label, suffixText: suffix),
        onChanged: (_) => field.didChange(_heightValue),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_heightUnit == HeightUnit.cm)
            input('Height', _height, suffix: 'cm')
          else
            Row(
              children: [
                Expanded(
                  child: input('Feet', _height, decimal: false, next: true),
                ),
                const SizedBox(width: Space.sm),
                Expanded(child: input('Inches', _inches)),
              ],
            ),
          FormProblem(field.errorText),
        ],
      );
    },
  );

  Future<void> _save() async {
    if (_saving || _photoBusy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _saveProblem = null;
    });
    try {
      final name = _name.text.trim();
      await ref.read(repositoryProvider).saveProfileDetails((
        displayName: name.isEmpty ? null : name,
        heightMillimeters: _heightValue,
        heightUnit: _heightUnit,
        weightUnit: _weightUnit,
      ));
      if (!mounted) return;
      ref.read(actionsProvider).saved();
      announce(context, 'Profile saved.');
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveProblem = describeError(
          error,
          fallback: 'Couldn’t save your profile.',
        );
      });
    }
  }

  Future<void> _changeAvatar() async {
    if (_photoBusy || _saving) return;
    FocusScope.of(context).unfocus();
    final choice = await showModalBottomSheet<Object>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(
        maxWidth: 540,
        maxHeight: MediaQuery.sizeOf(context).height * .78,
      ),
      builder: (context) => _AvatarPicker(profile: widget.profile),
    );
    if (!mounted || choice == null) return;
    setState(() {
      _photoBusy = true;
      _photoProblem = null;
    });
    try {
      final repo = ref.read(repositoryProvider);
      switch (choice) {
        case AvatarPreset preset:
          await repo.saveProfileAvatar(preset);
        case _PhotoAction.gallery:
          final photo = await ref.read(profilePhotosProvider).pick();
          if (!mounted || photo == null) return;
          await repo.saveProfilePhoto(photo);
        case _PhotoAction.remove:
          await repo.saveProfilePhoto(null);
      }
      if (mounted) announce(context, 'Avatar updated.');
    } catch (error) {
      if (mounted) {
        setState(
          () => _photoProblem = describeError(
            error,
            fallback: 'Couldn’t update your avatar. Try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recovery = ref.watch(recoverProfilePhotoProvider);
    final profile = widget.profile;
    final busy = _saving || _photoBusy;
    final choosing = busy || recovery.isLoading;
    return ProtectDraft<void>(
      dirty: _dirty,
      busy: busy,
      child: Form(
        key: _form,
        onChanged: () => setState(() {}),
        child: FormLayout(
          title: 'Edit profile',
          footer: ActionFooter(
            label: 'Save profile',
            onPressed: busy || !_dirty ? null : _save,
            busy: _saving,
          ),
          children: [
            const SizedBox(height: Space.lg),
            Column(
              children: [
                ProfileAvatar(
                  photo: profile.photo,
                  preset: profile.avatarPreset,
                ),
                const SizedBox(height: Space.xs),
                QuietButton('Change avatar', choosing ? null : _changeAvatar),
              ],
            ),
            if (_photoBusy) const LinearProgressIndicator(minHeight: 2),
            FormProblem(
              _photoProblem ??
                  (recovery.hasError
                      ? 'Couldn’t recover the last selected photo.'
                      : null),
            ),
            const SizedBox(height: Space.xl),
            TextFormField(
              controller: _name,
              enabled: !busy,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Display name',
                helperText: 'What should we call you?',
                helperMaxLines: 2,
              ),
              validator: (value) => displayNameError(value ?? ''),
            ),
            const SizedBox(height: Space.md),
            _heightInputs(busy),
            const SizedBox(height: Space.md),
            RowLink(
              title: 'Height unit',
              detail: _heightUnit.symbol,
              leading: const Icon(LucideIcons.ruler, size: 20),
              onTap: busy ? null : _chooseHeightUnit,
            ),
            RowLink(
              title: 'Weight unit',
              detail: _weightUnit.name,
              leading: const Icon(LucideIcons.scale, size: 20),
              onTap: busy
                  ? null
                  : () async {
                      FocusScope.of(context).unfocus();
                      final value = await chooseOption<WeightUnit>(
                        context,
                        'Weight unit',
                        [
                          for (final unit in WeightUnit.values)
                            (
                              value: unit,
                              label: unit.label,
                              subtitle: unit.name,
                            ),
                        ],
                        selected: _weightUnit,
                      );
                      if (mounted && value != null) {
                        setState(() => _weightUnit = value);
                      }
                    },
            ),
            FormProblem(_saveProblem),
          ],
        ),
      ),
    );
  }
}

enum _PhotoAction { gallery, remove }

class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({required this.profile});

  final LocalProfile profile;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      children: [
        const SectionTitle('Choose an avatar'),
        const SizedBox(height: Space.md),
        LayoutBuilder(
          builder: (context, limits) {
            final textSize = MediaQuery.textScalerOf(context).scale(13);
            final columns = limits.maxWidth >= 312 && textSize <= 18 ? 4 : 2;
            final width =
                (limits.maxWidth - (columns - 1) * Space.sm) / columns;
            return Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final preset in AvatarPreset.values)
                  SizedBox(
                    width: width,
                    child: _AvatarOption(
                      preset: preset,
                      selected:
                          profile.photo == null &&
                          profile.avatarPreset == preset,
                      onTap: () => Navigator.pop(context, preset),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: Space.md),
        const Divider(),
        RowLink(
          title: 'Choose from gallery',
          leading: const Icon(LucideIcons.image, size: 20),
          onTap: () => Navigator.pop(context, _PhotoAction.gallery),
          separator: profile.photo != null,
        ),
        if (profile.photo != null)
          RowLink(
            title: 'Remove photo',
            leading: const Icon(LucideIcons.trash2, size: 20),
            onTap: () => Navigator.pop(context, _PhotoAction.remove),
            separator: false,
          ),
      ],
    ),
  );
}

class _AvatarOption extends StatelessWidget {
  const _AvatarOption({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final AvatarPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Space.radius),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: Column(
          children: [
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? context.colors.green
                          : context.colors.border,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: ProfileAvatar(photo: null, preset: preset, size: 54),
                  ),
                ),
                if (selected)
                  ExcludeSemantics(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: context.colors.green,
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Icon(
                          LucideIcons.check,
                          size: 12,
                          color: context.colors.onGreen,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Space.xs),
            Text(
              preset.label,
              style: context.type.labelMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}
