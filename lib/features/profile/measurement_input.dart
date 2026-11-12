import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../shared/domain/body_metrics.dart';

String measurementText(BuildContext context, num value, {int decimals = 3}) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  return NumberFormat('0.${'#' * decimals}', locale).format(value);
}

String weightAmount(BuildContext context, int grams, WeightUnit unit) =>
    measurementText(context, grams / unit.grams, decimals: unit.decimals);

String weightText(BuildContext context, int grams, WeightUnit unit) =>
    '${weightAmount(context, grams, unit)} ${unit.name}';

String heightText(BuildContext context, int millimeters, HeightUnit unit) {
  if (unit == HeightUnit.cm) {
    return '${measurementText(context, millimeters / 10, decimals: 1)} cm';
  }
  final height = heightInFeetAndInches(millimeters);
  final inches = measurementText(context, height.inches, decimals: 2);
  return '${height.feet} ft $inches in';
}

int? parseMeasurement(String text, double scale, {required int decimals}) {
  final normalized = text.trim().replaceAll(',', '.');
  final pattern = RegExp(
    '^(?:[0-9]+(?:\\.[0-9]{0,$decimals})?|\\.[0-9]{1,$decimals})\$',
  );
  if (!pattern.hasMatch(normalized)) return null;
  final value = double.tryParse(normalized);
  if (value == null || !value.isFinite) return null;
  final scaled = value * scale;
  return scaled.isFinite ? scaled.round() : null;
}
