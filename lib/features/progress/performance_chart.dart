import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../shared/domain/training.dart';
import '../../shared/widgets/ui.dart';

enum ChartMetric {
  latest('Latest set'),
  best('Best set'),
  volume('Daily volume');

  const ChartMetric(this.label);
  final String label;

  int read(DailyResult day) => switch (this) {
    latest => day.latest,
    best => day.best,
    volume => day.total,
  };
}

class PerformanceChart extends StatefulWidget {
  const PerformanceChart({
    required this.days,
    required this.metric,
    required this.measurement,
    required this.durationStyle,
    super.key,
  });

  final List<DailyResult> days;
  final ChartMetric metric;
  final Measurement measurement;
  final DurationStyle durationStyle;

  @override
  State<PerformanceChart> createState() => _PerformanceChartState();
}

class _PerformanceChartState extends State<PerformanceChart> {
  CalendarDay? _selected;

  String _value(DailyResult day, {bool accessible = false}) => measure(
    widget.metric.read(day),
    widget.measurement,
    widget.durationStyle,
    accessible: accessible,
  );

  Future<void> _list() async {
    final selected = await showModalBottomSheet<CalendarDay>(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(
        maxWidth: 560,
        maxHeight: MediaQuery.sizeOf(context).height * .75,
      ),
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.metric.label} by date',
                style: context.type.titleLarge,
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.days.length,
                  itemBuilder: (context, index) {
                    final d = widget.days[widget.days.length - 1 - index];
                    return RowLink(
                      title: fullDay(d.day),
                      detail: _value(d, accessible: true),
                      onTap: () => Navigator.pop(context, d.day),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted && selected != null) setState(() => _selected = selected);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.days.isEmpty) return const SizedBox.shrink();
    final selected =
        widget.days.where((d) => d.day == _selected).firstOrNull ??
        widget.days.last;
    final textScale = MediaQuery.textScalerOf(context);
    final metric = widget.metric;
    final maxValue = widget.days.fold(
      0,
      (max, d) => math.max(max, metric.read(d)),
    );
    final step = _gridStep(maxValue);
    final ceiling = (maxValue / step).ceil() * step;
    final ticks = [
      0,
      for (var value = step; value <= ceiling; value += step) value,
    ];
    final labelStyle = context.type.labelSmall!;
    final tickText = ticks
        .map((v) => measureValue(v, widget.measurement, widget.durationStyle))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, limits) => Row(
            children: [
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  label:
                      '${fullDay(selected.day)}, ${metric.label.toLowerCase()}, ${_value(selected, accessible: true)}',
                  child: ExcludeSemantics(
                    child: Text(
                      '${shortDay(selected.day)}  ·  ${_value(selected)}',
                      style: context.type.labelMedium?.copyWith(
                        color: context.colors.green,
                      ),
                    ),
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: limits.maxWidth * .48),
                child: TextButton(
                  onPressed: _list,
                  child: const Text('View values', textAlign: TextAlign.center),
                ),
              ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height =
                (metric == ChartMetric.volume ? 122.0 : 173.0) +
                (textScale.scale(11) - 11).clamp(0.0, 24.0);
            final labelWidth = tickText
                .map((label) => _text(label, labelStyle, textScale).width)
                .reduce(math.max);
            final frame = _ChartFrame(
              Rect.fromLTRB(
                math.min(labelWidth + 10, width * .25),
                9,
                width - 12,
                height - textScale.scale(11) - 10,
              ),
              widget.days,
              metric,
              ceiling,
            );
            return GestureDetector(
              excludeFromSemantics: true,
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) => setState(
                () => _selected = frame.nearest(details.localPosition.dx).day,
              ),
              child: CustomPaint(
                size: Size(width, height),
                painter: _ChartPainter(
                  frame,
                  selected,
                  ticks,
                  tickText,
                  context.colors,
                  labelStyle,
                  textScale,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

TextPainter _text(String text, TextStyle style, TextScaler scale) =>
    TextPainter(
      text: TextSpan(text: text, style: style),
      textScaler: scale,
      textDirection: TextDirection.ltr,
    )..layout();

int _gridStep(int max) {
  final raw = math.max(1, max / 3);
  final power = math.pow(10, (math.log(raw) / math.ln10).floor()).toInt();
  final scaled = raw / power;
  return power *
      (scaled <= 1
          ? 1
          : scaled <= 2
          ? 2
          : scaled <= 5
          ? 5
          : 10);
}

class _ChartFrame {
  const _ChartFrame(this.rect, this.days, this.metric, this.ceiling);
  final Rect rect;
  final List<DailyResult> days;
  final ChartMetric metric;
  final int ceiling;

  int get span => days.last.day.daysSince(days.first.day);
  double get gutter => metric == ChartMetric.volume ? 8 : 3;

  double x(CalendarDay day) => span == 0
      ? rect.center.dx
      : rect.left +
            gutter +
            day.daysSince(days.first.day) / span * (rect.width - gutter * 2);

  Offset at(DailyResult day) => Offset(x(day.day), y(metric.read(day)));
  double y(int value) => rect.bottom - (value / ceiling * rect.height);

  DailyResult nearest(double tap) {
    var low = 0, high = days.length - 1;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (x(days[middle].day) < tap) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    if (low == 0) return days.first;
    return (x(days[low].day) - tap).abs() < (x(days[low - 1].day) - tap).abs()
        ? days[low]
        : days[low - 1];
  }

  Iterable<DailyResult> drawingDays() sync* {
    if (days.length <= rect.width ~/ 3) {
      yield* days;
      return;
    }
    var start = 0;
    while (start < days.length) {
      final bucket = ((x(days[start].day) - rect.left) / 4).floor();
      var end = start, min = start, max = start;
      while (end + 1 < days.length &&
          ((x(days[end + 1].day) - rect.left) / 4).floor() == bucket) {
        end++;
        if (metric.read(days[end]) < metric.read(days[min])) min = end;
        if (metric.read(days[end]) > metric.read(days[max])) max = end;
      }
      final indexes = metric == ChartMetric.volume
          ? [max]
          : ({
              if (start == 0) start,
              min,
              max,
              if (end == days.length - 1) end,
            }.toList()..sort());
      for (final index in indexes) {
        yield days[index];
      }
      start = end + 1;
    }
  }
}

class _ChartPainter extends CustomPainter {
  const _ChartPainter(
    this.frame,
    this.selected,
    this.ticks,
    this.labels,
    this.colors,
    this.style,
    this.scale,
  );
  final _ChartFrame frame;
  final DailyResult selected;
  final List<int> ticks;
  final List<String> labels;
  final TrackerColors colors;
  final TextStyle style;
  final TextScaler scale;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = frame.rect;
    final grid = Paint()
      ..color = colors.grid
      ..strokeWidth = 1;
    for (final (i, value) in ticks.indexed) {
      final y = frame.y(value);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), grid);
      final label = _text(labels[i], style, scale);
      label.paint(
        canvas,
        Offset(math.max(0, rect.left - label.width - 7), y - label.height / 2),
      );
    }
    final start = frame.days.first.day, end = frame.days.last.day;
    final slots = (rect.width / (scale.scale(42) + 20)).floor().clamp(1, 4);
    for (var index = 0; index <= (frame.span == 0 ? 0 : slots); index++) {
      final day = frame.span == 0
          ? start
          : start.plusDays((end.daysSince(start) * index / slots).round());
      if (frame.span > 0 && index > 0 && index < slots && frame.span < slots) {
        continue;
      }
      final label = _text(shortDay(day), style, scale);
      final left = (frame.x(day) - label.width / 2).clamp(
        rect.left,
        math.max(rect.left, size.width - label.width),
      );
      label.paint(canvas, Offset(left.toDouble(), rect.bottom + 6));
    }
    final point = frame.at(selected);
    final highlight = Paint()
      ..color = colors.muted
      ..strokeWidth = 1;
    for (var y = rect.top; y < rect.bottom; y += 6) {
      canvas.drawLine(
        Offset(point.dx, y),
        Offset(point.dx, math.min(y + 2.5, rect.bottom)),
        highlight,
      );
    }
    final shown = frame.drawingDays().toList();
    final green = Paint()..color = colors.green;
    if (frame.metric == ChartMetric.volume) {
      final barWidth = math.min(
        17.0,
        math.max(2.0, (rect.width - 16) / math.max(1, frame.span) * .66),
      );
      for (final day in shown) {
        final p = frame.at(day);
        canvas.drawRect(
          Rect.fromLTRB(
            p.dx - barWidth / 2,
            p.dy,
            p.dx + barWidth / 2,
            rect.bottom,
          ),
          green,
        );
      }
      canvas.drawRect(
        Rect.fromLTRB(
          point.dx - barWidth / 2,
          point.dy,
          point.dx + barWidth / 2,
          rect.bottom,
        ),
        Paint()..color = colors.ink,
      );
    } else {
      final line = Path();
      for (final (i, day) in shown.indexed) {
        final p = frame.at(day);
        if (i == 0) {
          line.moveTo(p.dx, p.dy);
        } else {
          line.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(
        line,
        Paint()
          ..color = colors.green
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      if (shown.length < 70) {
        for (final day in shown) {
          canvas.drawCircle(frame.at(day), 2.4, green);
        }
      }
      canvas.drawCircle(point, 5.2, Paint()..color = colors.background);
      canvas.drawCircle(point, 3.9, green);
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.frame.days != frame.days ||
      old.frame.rect != frame.rect ||
      old.frame.metric != frame.metric ||
      old.selected != selected ||
      old.colors != colors ||
      old.scale != scale ||
      old.style != style ||
      old.labels.join() != labels.join();
}

class Sparkline extends StatelessWidget {
  const Sparkline(this.days, {super.key});
  final List<DailyResult> days;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      painter: _SparkPainter(days, context.colors.green),
      size: const Size(132, 30),
    ),
  );
}

class _SparkPainter extends CustomPainter {
  const _SparkPainter(this.days, this.color);
  final List<DailyResult> days;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.length < 2) return;
    final lo = days.map((d) => d.latest).reduce(math.min);
    final hi = days.map((d) => d.latest).reduce(math.max);
    final duration = days.last.day.daysSince(days.first.day);
    final points = [
      for (final d in days)
        Offset(
          3 + d.day.daysSince(days.first.day) / duration * (size.width - 6),
          hi == lo
              ? size.height / 2
              : 3 + (hi - d.latest) / (hi - lo) * (size.height - 6),
        ),
    ];
    final path = Path()..addPolygon(points, false);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke,
    );
    final fill = Paint()..color = color;
    for (final p in points) {
      canvas.drawCircle(p, 2, fill);
    }
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.days != days || old.color != color;
}

class MetricTabs extends StatelessWidget {
  const MetricTabs({
    required this.selected,
    required this.onChanged,
    super.key,
  });
  final ChartMetric selected;
  final ValueChanged<ChartMetric> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 19,
    children: [
      for (final mode in [ChartMetric.latest, ChartMetric.best])
        Semantics(
          selected: selected == mode,
          child: TextButton(
            onPressed: () => onChanged(mode),
            style: TextButton.styleFrom(
              foregroundColor: selected == mode
                  ? context.colors.ink
                  : context.colors.muted,
              padding: EdgeInsets.zero,
              shape: const RoundedRectangleBorder(),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: selected == mode
                        ? context.colors.pill
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Text(mode.label),
              ),
            ),
          ),
        ),
    ],
  );
}

class FilterButton extends StatelessWidget {
  const FilterButton(
    this.label,
    this.onPressed, {
    this.icon = LucideIcons.chevronDown,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    style: OutlinedButton.styleFrom(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    onPressed: onPressed,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(label, style: context.type.titleSmall)),
        const SizedBox(width: 7),
        Icon(icon, size: 16),
      ],
    ),
  );
}
