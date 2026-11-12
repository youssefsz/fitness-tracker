import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TrackerColors extends ThemeExtension<TrackerColors> {
  const TrackerColors({
    required this.background,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.border,
    required this.input,
    required this.green,
    required this.onGreen,
    required this.add,
    required this.selection,
    required this.danger,
    required this.grid,
    required this.pill,
    required this.onPill,
  });

  static const light = TrackerColors(
    background: Color(0xfffafbf8),
    surface: Color(0xffffffff),
    ink: Color(0xff19271f),
    muted: Color(0xff637067),
    border: Color(0xffdfe5dd),
    input: Color(0xffeef2ea),
    green: Color(0xff176b45),
    onGreen: Colors.white,
    add: Color(0xffb5ec7c),
    selection: Color(0xffe7efdf),
    danger: Color(0xffb42318),
    grid: Color(0xffd9e1d8),
    pill: Color(0xff222d26),
    onPill: Colors.white,
  );
  static const dark = TrackerColors(
    background: Color(0xff141d17),
    surface: Color(0xff202d24),
    ink: Color(0xffedf4eb),
    muted: Color(0xffadbbad),
    border: Color(0xff3a4c3e),
    input: Color(0xff25332a),
    green: Color(0xff91d8a9),
    onGreen: Color(0xff102e20),
    add: Color(0xffb5ec7c),
    selection: Color(0xff293e30),
    danger: Color(0xffffaaa0),
    grid: Color(0xff3b4d40),
    pill: Color(0xffdaeadd),
    onPill: Color(0xff19271f),
  );

  final Color background,
      surface,
      ink,
      muted,
      border,
      input,
      green,
      onGreen,
      add,
      selection,
      danger,
      grid,
      pill,
      onPill;

  @override
  TrackerColors copyWith() => this;

  @override
  TrackerColors lerp(TrackerColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return TrackerColors(
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      ink: mix(ink, other.ink),
      muted: mix(muted, other.muted),
      border: mix(border, other.border),
      input: mix(input, other.input),
      green: mix(green, other.green),
      onGreen: mix(onGreen, other.onGreen),
      add: mix(add, other.add),
      selection: mix(selection, other.selection),
      danger: mix(danger, other.danger),
      grid: mix(grid, other.grid),
      pill: mix(pill, other.pill),
      onPill: mix(onPill, other.onPill),
    );
  }
}

abstract final class Space {
  static const double xs = 4, sm = 8, md = 16, lg = 24, xl = 32, xxl = 40;
  static const double target = 48, radius = 12, split = 760;
}

extension TrackerContext on BuildContext {
  TrackerColors get colors => Theme.of(this).extension<TrackerColors>()!;
  TextTheme get type => Theme.of(this).textTheme;
  bool get dark => Theme.of(this).brightness == Brightness.dark;
}

const numeric = [FontFeature.tabularFigures()];

ThemeData trackerTheme(Brightness brightness) {
  final c = brightness == Brightness.dark
      ? TrackerColors.dark
      : TrackerColors.light;
  final scheme =
      ColorScheme.fromSeed(seedColor: c.green, brightness: brightness).copyWith(
        primary: c.green,
        onPrimary: c.onGreen,
        surface: c.surface,
        onSurface: c.ink,
        onSurfaceVariant: c.muted,
        outline: c.muted,
        outlineVariant: c.border,
        error: c.danger,
        secondaryContainer: c.selection,
        onSecondaryContainer: c.ink,
      );
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: c.background,
    extensions: [c],
    visualDensity: VisualDensity.standard,
  );
  final type = base.textTheme.apply(bodyColor: c.ink, displayColor: c.ink);
  TextStyle style(
    TextStyle? style,
    double size,
    FontWeight weight, {
    double height = 1.23,
    double spacing = 0,
    Color? color,
  }) => (style ?? const TextStyle()).copyWith(
    fontSize: size,
    fontWeight: weight,
    color: color ?? c.ink,
    letterSpacing: spacing,
    height: height,
    fontFeatures: numeric,
  );
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(Space.radius),
  );
  OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: color, width: width),
      );

  return base.copyWith(
    textTheme: type.copyWith(
      headlineLarge: style(
        type.headlineLarge,
        34,
        FontWeight.w700,
        spacing: -0.9,
        height: 1.10,
      ),
      headlineMedium: style(
        type.headlineMedium,
        30,
        FontWeight.w700,
        spacing: -0.7,
        height: 1.11,
      ),
      headlineSmall: style(
        type.headlineSmall,
        24,
        FontWeight.w700,
        spacing: -0.45,
      ),
      titleLarge: style(type.titleLarge, 22, FontWeight.w700, spacing: -0.35),
      titleMedium: style(type.titleMedium, 17, FontWeight.w600, spacing: -0.12),
      titleSmall: style(type.titleSmall, 15, FontWeight.w600),
      bodyLarge: style(type.bodyLarge, 16, FontWeight.w400, height: 1.4),
      bodyMedium: style(type.bodyMedium, 14, FontWeight.w400, height: 1.36),
      bodySmall: style(
        type.bodySmall,
        13,
        FontWeight.w400,
        height: 1.34,
        color: c.muted,
      ),
      labelLarge: style(type.labelLarge, 14, FontWeight.w600),
      labelMedium: style(type.labelMedium, 13, FontWeight.w600),
      labelSmall: style(type.labelSmall, 11, FontWeight.w500, color: c.muted),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.green,
      selectionColor: c.selection,
      selectionHandleColor: c.green,
    ),
    dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: c.background,
      foregroundColor: c.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: trackerBars(brightness),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.green,
        foregroundColor: c.onGreen,
        minimumSize: const Size(48, 50),
        shape: shape,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        side: BorderSide(color: c.border),
        shape: shape,
        minimumSize: const Size(48, 48),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.green,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        shape: shape,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.input,
      border: inputBorder(Colors.transparent),
      enabledBorder: inputBorder(Colors.transparent),
      focusedBorder: inputBorder(c.green, 1.5),
      errorBorder: inputBorder(c.danger),
      focusedErrorBorder: inputBorder(c.danger, 1.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      hintStyle: TextStyle(color: c.muted, fontSize: 15),
      helperStyle: TextStyle(color: c.muted),
      errorStyle: TextStyle(color: c.danger),
      errorMaxLines: 4,
    ),
    dialogTheme: DialogThemeData(backgroundColor: c.surface, shape: shape),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.pill,
      contentTextStyle: TextStyle(color: c.onPill),
      behavior: SnackBarBehavior.floating,
      shape: shape,
    ),
  );
}

SystemUiOverlayStyle trackerBars(Brightness brightness) => SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarBrightness: brightness,
  statusBarIconBrightness: brightness == Brightness.dark
      ? Brightness.light
      : Brightness.dark,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarContrastEnforced: false,
  systemNavigationBarIconBrightness: brightness == Brightness.dark
      ? Brightness.light
      : Brightness.dark,
);
