import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../domain/training.dart';

String shortDay(CalendarDay day) => DateFormat('d MMM').format(day.utc);
String fullDay(CalendarDay day) => DateFormat('d MMM yyyy').format(day.utc);
String weekday(CalendarDay day) => DateFormat('EEEE, d MMMM').format(day.utc);
String monthName(DateTime month) => DateFormat('MMMM yyyy').format(month);

String describeError(
  Object error, {
  String fallback = 'Something went wrong. Please try again.',
}) => switch (error) {
  TrackerException(:final message) => message,
  FormatException(:final message) => message,
  _ => fallback,
};

void announce(BuildContext context, String text) {
  final messenger = ScaffoldMessenger.of(context);
  // Publish after the current frame. A successful save can pop its route
  // before the messenger lays out the notice on the destination screen.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!messenger.mounted) return;
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
      snackBarAnimationStyle: AnimationStyle.noAnimation,
    );
  });
  WidgetsBinding.instance.ensureVisualUpdate();
}

class AsyncPanel<T> extends StatelessWidget {
  const AsyncPanel(
    this.value, {
    required this.builder,
    required this.retry,
    super.key,
  });
  final AsyncValue<T> value;
  final Widget Function(T) builder;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) {
    if (value.hasValue) return builder(value.requireValue);
    if (value.hasError) {
      return EmptyBlock(
        title: 'Couldn’t load this view',
        message: describeError(
          value.error!,
          fallback: 'Try reading your local records again.',
        ),
        action: 'Try again',
        onAction: retry,
      );
    }
    return const SizedBox(
      height: 180,
      child: Center(
        child: SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class EmptyBlock extends StatelessWidget {
  const EmptyBlock({
    required this.title,
    required this.message,
    this.action,
    this.onAction,
    super.key,
  });
  final String title, message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.type.titleLarge),
        const SizedBox(height: Space.sm),
        Text(
          message,
          style: context.type.bodyLarge?.copyWith(color: context.colors.muted),
        ),
        if (action != null) ...[
          const SizedBox(height: Space.md),
          FilledButton(onPressed: onAction, child: Text(action!)),
        ],
      ],
    ),
  );
}

class ScreenScroll extends StatelessWidget {
  const ScreenScroll({
    required this.children,
    this.primary = false,
    this.width = 720,
    this.controller,
    this.scrollKey,
    super.key,
  });

  final List<Widget> children;
  final bool primary;
  final double width;
  final ScrollController? controller;
  final Key? scrollKey;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: primary,
    bottom: false,
    child: LayoutBuilder(
      builder: (context, limits) {
        final side = limits.maxWidth < 350 ? 16.0 : 24.0;
        return CustomScrollView(
          key: scrollKey,
          controller: controller,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            for (final child in children)
              SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: width),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: side),
                      child: SizedBox(width: double.infinity, child: child),
                    ),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: primary
                    ? 110 + MediaQuery.paddingOf(context).bottom
                    : 28 + MediaQuery.paddingOf(context).bottom,
              ),
            ),
          ],
        );
      },
    ),
  );
}

class ResponsiveSplit extends StatelessWidget {
  const ResponsiveSplit({
    required this.main,
    required this.side,
    this.gap = 40,
    super.key,
  });
  final Widget main, side;
  final double gap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth >= Space.split
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: main),
              SizedBox(width: gap),
              Expanded(flex: 5, child: side),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              main,
              const SizedBox(height: Space.xl),
              side,
            ],
          ),
  );
}

class ScreenHeading extends StatelessWidget {
  const ScreenHeading(
    this.title, {
    this.subtitle,
    this.action,
    this.top = 16,
    super.key,
  });
  final String title;
  final String? subtitle;
  final Widget? action;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: top, bottom: Space.md),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(title, style: context.type.headlineLarge),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: Space.xs),
                Text(
                  subtitle!,
                  style: context.type.bodyMedium?.copyWith(
                    color: context.colors.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (action != null) ...[const SizedBox(width: Space.sm), action!],
      ],
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {this.action, super.key});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, limits) => Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title, style: context.type.titleLarge),
          ),
        ),
        if (action != null) ...[
          const SizedBox(width: Space.sm),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: limits.maxWidth * .42),
            child: action!,
          ),
        ],
      ],
    ),
  );
}

class QuietButton extends StatelessWidget {
  const QuietButton(
    this.label,
    this.onPressed, {
    this.icon,
    this.danger = false,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool danger;

  @override
  Widget build(BuildContext context) => TextButton(
    style: TextButton.styleFrom(
      foregroundColor: danger ? context.colors.danger : context.colors.green,
      alignment: AlignmentDirectional.centerStart,
    ),
    onPressed: onPressed,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 6)],
        Flexible(child: Text(label)),
      ],
    ),
  );
}

class RoundControl extends StatelessWidget {
  const RoundControl(this.icon, this.label, this.onPressed, {super.key});
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    onPressed: onPressed,
    constraints: const BoxConstraints.tightFor(width: 48, height: 48),
    icon: Icon(icon, size: 21),
  );
}

PreferredSizeWidget secondaryBar(
  BuildContext context, {
  String? title,
  String? back,
  List<Widget>? actions,
}) => AppBar(
  automaticallyImplyLeading: false,
  centerTitle: title != null,
  title: title == null
      ? null
      : Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
  titleTextStyle: context.type.titleMedium,
  leading: back == null
      ? BackButton(onPressed: () => Navigator.maybePop(context))
      : TextButton(
          onPressed: () => Navigator.maybePop(context),
          child: Text(back),
        ),
  leadingWidth: back == null ? 56 : 88,
  actions: actions,
);

class ActionFooter extends StatelessWidget {
  const ActionFooter({
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.secondary,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.colors.background,
    child: SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 10),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton(
                  onPressed: busy ? null : onPressed,
                  child: busy
                      ? const SizedBox.square(
                          dimension: 19,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(label, textAlign: TextAlign.center),
                ),
                if (secondary != null) Center(child: secondary!),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class FormLayout extends StatelessWidget {
  const FormLayout({
    required this.title,
    required this.children,
    required this.footer,
    this.width = 720,
    super.key,
  });
  final String title;
  final List<Widget> children;
  final Widget footer;
  final double width;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: secondaryBar(context, title: title, back: 'Cancel'),
    body: ScreenScroll(width: width, children: children),
    bottomNavigationBar: KeyboardFooter(child: footer),
  );
}

/// Place the footer above the keyboard and let Scaffold place notices above it.
class KeyboardFooter extends StatelessWidget {
  const KeyboardFooter({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: child,
  );
}

class RowLink extends StatelessWidget {
  const RowLink({
    required this.title,
    this.subtitle,
    this.detail,
    this.icon,
    this.onTap,
    this.leading,
    this.separator = true,
    super.key,
  });
  final String title;
  final String? subtitle, detail;
  final IconData? icon;
  final Widget? leading;
  final VoidCallback? onTap;
  final bool separator;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Space.target),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 12)],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: context.type.titleSmall),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(subtitle!, style: context.type.bodySmall),
                        ],
                      ],
                    ),
                  ),
                  if (detail != null)
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(left: Space.sm),
                        child: Text(
                          detail!,
                          style: context.type.bodySmall,
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ),
                  if (icon != null || onTap != null) ...[
                    const SizedBox(width: Space.sm),
                    Icon(
                      icon ?? LucideIcons.chevronRight,
                      size: 18,
                      color: context.colors.muted,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      if (separator) const Divider(),
    ],
  );
}

class FormProblem extends StatelessWidget {
  const FormProblem(this.message, {super.key});
  final String? message;
  @override
  Widget build(BuildContext context) => message == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.sm),
          child: Semantics(
            liveRegion: true,
            child: Text(
              message!,
              style: context.type.bodyMedium?.copyWith(
                color: context.colors.danger,
              ),
            ),
          ),
        );
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String label,
  bool destructive = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: destructive
                  ? context.colors.danger
                  : context.colors.green,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(label),
          ),
        ],
      ),
    ) ??
    false;

Future<CalendarDay?> pickDay(
  BuildContext context,
  CalendarDay current, {
  required CalendarDay latest,
  CalendarDay first = CalendarDay.earliest,
  String? title,
}) async {
  final date = await showDatePicker(
    context: context,
    initialDate:
        (current.isBefore(first)
                ? first
                : current.isAfter(latest)
                ? latest
                : current)
            .local,
    firstDate: first.local,
    lastDate: latest.local,
    helpText: title,
  );
  return date == null ? null : CalendarDay.fromDate(date);
}

Future<T?> chooseOption<T extends Object>(
  BuildContext context,
  String title,
  List<({T value, String label, String? subtitle})> options, {
  T? selected,
}) => showModalBottomSheet<T>(
  useRootNavigator: true,
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  constraints: BoxConstraints(
    maxWidth: 540,
    maxHeight: MediaQuery.sizeOf(context).height * .78,
  ),
  builder: (context) => SafeArea(
    top: false,
    child: ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(title, style: context.type.titleLarge),
        ),
        for (final option in options)
          Semantics(
            selected: option.value == selected,
            child: RowLink(
              title: option.label,
              subtitle: option.subtitle,
              icon: option.value == selected
                  ? LucideIcons.check
                  : LucideIcons.chevronRight,
              onTap: () => Navigator.pop(context, option.value),
            ),
          ),
      ],
    ),
  ),
);

class SearchInput extends StatelessWidget {
  const SearchInput({
    required this.hint,
    required this.onChanged,
    this.autofocus = false,
    this.controller,
    super.key,
  });
  final String hint;
  final ValueChanged<String> onChanged;
  final bool autofocus;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    autofocus: autofocus,
    onChanged: onChanged,
    textInputAction: TextInputAction.search,
    decoration: InputDecoration(
      hintText: hint,
      prefixIcon: Icon(
        LucideIcons.search,
        size: 18,
        color: context.colors.muted,
      ),
    ),
  );
}

class ProtectDraft<T> extends StatefulWidget {
  const ProtectDraft({
    required this.dirty,
    required this.busy,
    required this.child,
    super.key,
  });
  final bool dirty, busy;
  final Widget child;

  @override
  State<ProtectDraft<T>> createState() => _ProtectDraftState<T>();
}

class _ProtectDraftState<T> extends State<ProtectDraft<T>> {
  bool _asking = false;

  @override
  Widget build(BuildContext context) => PopScope<T>(
    canPop: !widget.dirty && !widget.busy,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop || widget.busy || !widget.dirty || _asking) return;
      _asking = true;
      final discard = await confirmAction(
        context,
        title: 'Discard changes?',
        message: 'Your unsaved changes will be lost.',
        label: 'Discard',
        destructive: true,
      );
      _asking = false;
      if (context.mounted && discard) Navigator.pop(context);
    },
    child: widget.child,
  );
}
