import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../shared/domain/training.dart';
import '../../shared/widgets/ui.dart';
import 'performance_chart.dart';

typedef RangeSelection = ({
  RangePreset preset,
  CalendarDay? start,
  CalendarDay? end,
});
const allTime = (preset: RangePreset.all, start: null, end: null);

DayRange selectionBounds(RangeSelection range, CalendarDay today) =>
    range.preset == RangePreset.custom
    ? (start: range.start, end: range.end)
    : range.preset.boundaries(today);

Future<RangeSelection?> selectRange(
  BuildContext context,
  RangeSelection initial,
  CalendarDay today,
) => Navigator.of(context, rootNavigator: true).push<RangeSelection>(
  MaterialPageRoute(
    builder: (_) => DateRangePage(initial: initial, today: today),
  ),
);

class DateRangePage extends StatefulWidget {
  const DateRangePage({required this.initial, required this.today, super.key});
  final RangeSelection initial;
  final CalendarDay today;

  @override
  State<DateRangePage> createState() => _DateRangePageState();
}

class _DateRangePageState extends State<DateRangePage> {
  late var _preset = widget.initial.preset;
  late var _start = widget.initial.start ?? widget.today.plusDays(-29);
  late var _end = widget.initial.end ?? widget.today;

  Future<void> _change(bool start) async {
    final date = await pickDay(
      context,
      start ? _start : _end,
      latest: widget.today,
      title: start ? 'Choose start date' : 'Choose end date',
    );
    if (date == null || !mounted) return;
    setState(() {
      if (start) {
        _start = date;
      } else {
        _end = date;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final invalid = _preset == RangePreset.custom && _start.isAfter(_end);
    return FormLayout(
      title: 'Date range',
      footer: ActionFooter(
        label: 'Apply range',
        onPressed: invalid
            ? null
            : () => Navigator.pop(context, (
                preset: _preset,
                start: _start,
                end: _end,
              )),
      ),
      children: [
        const SizedBox(height: 8),
        RadioGroup<RangePreset>(
          groupValue: _preset,
          onChanged: (value) {
            if (value != null) setState(() => _preset = value);
          },
          child: Column(
            children: [
              for (final choice in RangePreset.values) ...[
                RadioListTile<RangePreset>(
                  value: choice,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.trailing,
                  title: Text(choice.label),
                ),
                const Divider(),
              ],
            ],
          ),
        ),
        if (_preset == RangePreset.custom) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilterButton(
                'From ${fullDay(_start)}',
                () => _change(true),
                icon: LucideIcons.calendarDays,
              ),
              FilterButton(
                'To ${fullDay(_end)}',
                () => _change(false),
                icon: LucideIcons.calendarDays,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (invalid)
            const FormProblem(
              'The end date must be on or after the start date.',
            )
          else
            Text('Both dates are included.', style: context.type.bodySmall),
        ],
        const SizedBox(height: 24),
        Text(
          'Statistics use only the records in this range.',
          style: context.type.bodySmall,
        ),
      ],
    );
  }
}
