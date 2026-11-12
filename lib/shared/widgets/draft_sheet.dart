import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import 'ui.dart';

/// Gives drag, backdrop taps and the handle's accessibility action the same
/// draft protection, while leaving the content in charge of its Back action.
class DraftSheetRoute<T> extends ModalBottomSheetRoute<T> {
  DraftSheetRoute({required BuildContext context, required super.builder})
    : super(
        isScrollControlled: true,
        useSafeArea: true,
        constraints: const BoxConstraints(maxWidth: 640),
        showDragHandle: true,
        barrierLabel: MaterialLocalizations.of(context).scrimLabel,
        barrierOnTapHint: MaterialLocalizations.of(context)
            .scrimOnTapHint(MaterialLocalizations.of(context).bottomSheetLabel),
        sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
            ? AnimationStyle.noAnimation
            : null,
      );

  bool Function()? hasProtectedDraft;
  VoidCallback? onDismissBlocked;
  bool _finishing = false;

  void finish([T? result]) {
    _finishing = true;
    try {
      navigator!.pop<T>(result);
    } finally {
      _finishing = false;
    }
  }

  @override
  bool didPop(T? result) {
    if (!_finishing && hasProtectedDraft?.call() == true) {
      // BottomSheet may have started a reverse animation at the end of a drag.
      controller?.forward();
      scheduleMicrotask(() {
        if (isCurrent) onDismissBlocked?.call();
      });
      return false;
    }
    return super.didPop(result);
  }

  @override
  Widget buildModalBarrier() => AnimatedModalBarrier(
    color: animation!.drive(
      ColorTween(
        begin: barrierColor.withValues(alpha: 0),
        end: barrierColor,
      ).chain(CurveTween(curve: barrierCurve)),
    ),
    dismissible: true,
    semanticsLabel: barrierLabel,
    semanticsOnTapHint: barrierOnTapHint,
    barrierSemanticsDismissible: semanticsDismissible,
    onDismiss: () {
      if (isCurrent) navigator!.pop<T>();
    },
  );
}

class SheetLayout extends StatelessWidget {
  const SheetLayout({
    required this.title,
    required this.closeLabel,
    required this.close,
    required this.child,
    this.back,
    this.footer,
    super.key,
  });

  final String title, closeLabel;
  final VoidCallback? back, close;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: LayoutBuilder(
        builder: (context, limits) => SizedBox(
          height: (limits.maxHeight * (keyboard > 0 ? 1 : 0.84)).clamp(
            0.0,
            720.0,
          ),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                  Space.pageInset(limits.maxWidth),
                  0,
                  Space.sm,
                  Space.sm,
                ),
                child: Row(
                  children: [
                    if (back != null)
                      RoundControl(LucideIcons.chevronLeft, 'Back', back),
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(title, style: context.type.titleLarge),
                      ),
                    ),
                    RoundControl(LucideIcons.x, closeLabel, close),
                  ],
                ),
              ),
              Expanded(child: child),
              if (footer case final footer?)
                footer
              else
                SizedBox(height: MediaQuery.paddingOf(context).bottom),
            ],
          ),
        ),
      ),
    );
  }
}
