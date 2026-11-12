import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../shared/domain/training.dart';
import '../../shared/widgets/ui.dart';

String appearanceLabel(Appearance appearance) => switch (appearance) {
  Appearance.system => 'System',
  Appearance.light => 'Light',
  Appearance.dark => 'Dark',
};

Future<Appearance?> pickAppearance(BuildContext context, Appearance current) =>
    showModalBottomSheet<Appearance>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 480),
      builder: (context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SectionTitle('Appearance'),
              const SizedBox(height: Space.md),
              LayoutBuilder(
                builder: (context, size) {
                  final stacked =
                      size.maxWidth < 260 ||
                      MediaQuery.textScalerOf(context).scale(16) > 23;
                  final options = [
                    for (final appearance in Appearance.values)
                      _AppearanceOption(
                        appearance: appearance,
                        selected: appearance == current,
                        stacked: stacked,
                        onTap: () => Navigator.pop(context, appearance),
                      ),
                  ];
                  if (stacked) return Column(children: options);
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: Space.sm,
                    children: [
                      for (final option in options) Expanded(child: option),
                    ],
                  );
                },
              ),
              const SizedBox(height: Space.md),
              Text(
                'System follows your device setting.',
                style: context.type.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );

class _AppearanceOption extends StatelessWidget {
  const _AppearanceOption({
    required this.appearance,
    required this.selected,
    required this.stacked,
    required this.onTap,
  });

  final Appearance appearance;
  final bool selected, stacked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BorderRadius.circular(Space.radius);
    final preview = ExcludeSemantics(
      child: AspectRatio(
        aspectRatio: 1.28,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: radius,
              child: CustomPaint(painter: _PreviewPainter(appearance)),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: selected ? colors.green : colors.border,
                  width: selected ? 2 : 1,
                ),
              ),
            ),
            if (selected && !stacked)
              PositionedDirectional(
                top: 6,
                end: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.green,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Icon(
                      LucideIcons.check,
                      size: 12,
                      color: colors.onGreen,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    final label = Text(
      appearanceLabel(appearance),
      style: context.type.titleSmall,
    );
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: stacked
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.xs),
                child: Row(
                  children: [
                    SizedBox(width: 72, child: preview),
                    const SizedBox(width: Space.md),
                    Expanded(child: label),
                    if (selected)
                      ExcludeSemantics(
                        child: Icon(LucideIcons.check, color: colors.green),
                      ),
                  ],
                ),
              )
            : Column(
                children: [
                  preview,
                  const SizedBox(height: Space.sm),
                  label,
                ],
              ),
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  const _PreviewPainter(this.appearance);
  final Appearance appearance;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint();

    void block(
      Color color,
      double left,
      double top,
      double width,
      double height,
    ) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w * left, h * top, w * width, h * height),
          Radius.circular(h * height / 2),
        ),
        paint..color = color,
      );
    }

    void preview(TrackerColors colors) {
      canvas.drawRect(Offset.zero & size, paint..color = colors.background);
      block(colors.ink, .13, .18, .42, .065);
      block(colors.input, .13, .34, .74, .14);
      block(colors.input, .13, .52, .74, .14);
      block(colors.selection, .13, .77, .53, .12);
      block(colors.pill, .16, .79, .17, .08);
      canvas.drawCircle(
        Offset(w * .80, h * .83),
        h * .064,
        paint..color = colors.add,
      );
    }

    if (appearance == Appearance.dark) {
      preview(TrackerColors.dark);
    } else {
      preview(TrackerColors.light);
      if (appearance == Appearance.system) {
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(w / 2, 0, w / 2, h));
        preview(TrackerColors.dark);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_PreviewPainter oldDelegate) =>
      appearance != oldDelegate.appearance;
}
