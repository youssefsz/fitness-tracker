import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../shared/domain/body_metrics.dart';
import '../../shared/domain/training.dart';
import '../../shared/widgets/ui.dart';
import 'measurement_input.dart';

class WeightHistoryPage extends ConsumerStatefulWidget {
  const WeightHistoryPage({super.key});

  @override
  ConsumerState<WeightHistoryPage> createState() => _WeightHistoryPageState();
}

class _WeightHistoryPageState extends ConsumerState<WeightHistoryPage> {
  static const _pageSize = 30;
  int _limit = _pageSize;

  @override
  Widget build(BuildContext context) {
    final filter = (limit: _limit + 1, since: null);
    final unit =
        ref.watch(profileProvider).value?.details.weightUnit ?? WeightUnit.kg;
    return Scaffold(
      appBar: secondaryBar(context),
      body: ScreenScroll(
        children: [
          const ScreenHeading('Weight history', top: 0),
          AsyncPanel(
            ref.watch(weighInsProvider(filter)),
            retry: () => ref.invalidate(weighInsProvider(filter)),
            builder: (records) {
              final latest = records.firstOrNull;
              if (latest == null) {
                return EmptyBlock(
                  title: 'No weigh-ins yet',
                  message: 'Log your first weight to start a history.',
                  action: 'Log weight',
                  onAction: () => context.push('/profile/weigh-in'),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: Space.lg,
                    runSpacing: Space.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            weightText(context, latest.grams, unit),
                            style: context.type.headlineSmall,
                          ),
                          Text(
                            'Latest · ${fullDay(latest.day)}',
                            style: context.type.bodySmall,
                          ),
                        ],
                      ),
                      FilledButton.icon(
                        onPressed: () => context.push('/profile/weigh-in'),
                        icon: const Icon(LucideIcons.plus, size: 18),
                        label: const Text('Log weight'),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.xl),
                  _WeightTrend(latest: latest.day, unit: unit),
                  const SizedBox(height: Space.xl),
                  const SectionTitle('Weigh-ins'),
                  const SizedBox(height: Space.xs),
                  for (final record in records.take(_limit))
                    RowLink(
                      title: fullDay(record.day),
                      detail: weightText(context, record.grams, unit),
                      onTap: () =>
                          context.push('/profile/weigh-in', extra: record),
                    ),
                  if (records.length > _limit)
                    QuietButton(
                      'Load more',
                      () => setState(() => _limit += _pageSize),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _WeightTrend extends ConsumerWidget {
  const _WeightTrend({required this.latest, required this.unit});

  final CalendarDay latest;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = (limit: null, since: latest.plusDays(-89));
    return AsyncPanel(
      ref.watch(weighInsProvider(filter)),
      retry: () => ref.invalidate(weighInsProvider(filter)),
      builder: (records) {
        if (records.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('Recent trend'),
            const SizedBox(height: Space.xs),
            Text(
              '90 days through ${fullDay(latest)}',
              style: context.type.bodySmall,
            ),
            const SizedBox(height: Space.md),
            _WeightChart(records: records.reversed.toList(), unit: unit),
          ],
        );
      },
    );
  }
}

class _WeightChart extends StatelessWidget {
  const _WeightChart({required this.records, required this.unit});

  final List<WeighIn> records;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final lowest = records.map((r) => r.grams).reduce(math.min);
    final highest = records.map((r) => r.grams).reduce(math.max);
    final bottom = math.max(0, lowest - 500);
    final top = math.max(bottom + 1000, highest + 500);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: math.max(144, 65 * scale),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final grams in [top, (top + bottom) / 2, bottom])
                      Text(
                        measurementText(
                          context,
                          grams / unit.grams,
                          decimals: 1,
                        ),
                        style: context.type.bodySmall,
                      ),
                  ],
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8 * scale),
                    child: CustomPaint(
                      painter: _WeightLine(
                        records: records,
                        bottom: bottom,
                        top: top,
                        ink: context.colors.green,
                        grid: context.colors.grid,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.xs),
          Text(
            records.length == 1
                ? '${fullDay(records.first.day)} · ${unit.name}'
                : '${fullDay(records.first.day)} to ${fullDay(records.last.day)} · ${unit.name}',
            style: context.type.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _WeightLine extends CustomPainter {
  const _WeightLine({
    required this.records,
    required this.bottom,
    required this.top,
    required this.ink,
    required this.grid,
  });

  final List<WeighIn> records;
  final int bottom, top;
  final Color ink, grid;

  @override
  void paint(Canvas canvas, Size size) {
    final guide = Paint()..color = grid;
    for (final y in [0.0, size.height / 2, size.height]) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), guide);
    }
    final first = records.first.day;
    final span = records.last.day.daysSince(first);
    final width = math.max(0.0, size.width - 8);
    final points = [
      for (final record in records)
        Offset(
          span == 0
              ? size.width / 2
              : 4 + width * record.day.daysSince(first) / span,
          size.height * (top - record.grams) / (top - bottom),
        ),
    ];
    final line = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(Path()..addPolygon(points, false), line);
    final dot = Paint()..color = ink;
    for (final point in points) {
      canvas.drawCircle(point, points.length <= 30 ? 3 : 1.5, dot);
    }
  }

  @override
  bool shouldRepaint(_WeightLine oldDelegate) =>
      oldDelegate.records != records ||
      oldDelegate.bottom != bottom ||
      oldDelegate.top != top ||
      oldDelegate.ink != ink ||
      oldDelegate.grid != grid;
}

class WeightFormPage extends ConsumerWidget {
  const WeightFormPage({this.original, super.key});

  final WeighIn? original;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(profileProvider);
    final profile = result.value;
    if (profile != null) {
      return _WeightEditor(
        original: original,
        unit: profile.details.weightUnit,
      );
    }
    return FormLayout(
      title: original == null ? 'Log weight' : 'Edit weigh-in',
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

class _WeightEditor extends ConsumerStatefulWidget {
  const _WeightEditor({required this.original, required this.unit});

  final WeighIn? original;
  final WeightUnit unit;

  @override
  ConsumerState<_WeightEditor> createState() => _WeightEditorState();
}

class _WeightEditorState extends ConsumerState<_WeightEditor> {
  final _form = GlobalKey<FormState>();
  final _weight = TextEditingController();
  late final CalendarDay _initialDay =
      widget.original?.day ?? ref.read(todayProvider);
  late CalendarDay _day = _initialDay;
  late final WeightUnit _initialUnit = widget.unit;
  late WeightUnit _unit = _initialUnit;
  late int? _grams = widget.original?.grams;
  bool _initialized = false, _busy = false;
  String? _problem;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    if (widget.original case final original?) {
      _weight.text = weightAmount(context, original.grams, _unit);
    }
  }

  @override
  void dispose() {
    _weight.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _day != _initialDay ||
      _unit != _initialUnit ||
      (widget.original == null
          ? _weight.text.trim().isNotEmpty
          : _grams != widget.original!.grams);

  void _editAmount(String text) => setState(() {
    _grams = parseMeasurement(text, _unit.grams, decimals: _unit.decimals);
  });

  void _selectUnit(WeightUnit unit) {
    if (unit == _unit) return;
    final grams = _grams;
    setState(() {
      _unit = unit;
      if (grams != null && grams > 0 && grams <= maxWeightGrams) {
        final converted = weightAmount(context, grams, unit);
        _weight.value = TextEditingValue(
          text: converted,
          selection: TextSelection.collapsed(offset: converted.length),
        );
      } else {
        _grams = parseMeasurement(
          _weight.text,
          unit.grams,
          decimals: unit.decimals,
        );
      }
    });
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    final repo = ref.read(repositoryProvider);
    final value = (day: _day, grams: _grams!);
    await _write(
      () => repo.saveWeighIn(
        value,
        original: widget.original,
        displayUnit: _unit == _initialUnit ? null : _unit,
      ),
      'Weight saved.',
      'Couldn’t save this weigh-in.',
    );
  }

  Future<void> _delete(WeighIn original) async {
    FocusScope.of(context).unfocus();
    final confirmed = await confirmAction(
      context,
      title: 'Delete this weigh-in?',
      message:
          'The weight recorded on ${fullDay(original.day)} will be removed from your history.',
      label: 'Delete weigh-in',
      destructive: true,
    );
    if (!mounted || !confirmed) return;
    final repo = ref.read(repositoryProvider);
    await _write(
      () => repo.deleteWeighIn(original),
      'Weigh-in deleted.',
      'Couldn’t delete this weigh-in.',
    );
  }

  Future<void> _write(
    Future<void> Function() action,
    String confirmation,
    String fallback,
  ) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await action();
      if (!mounted) return;
      ref.read(actionsProvider).saved();
      announce(context, confirmation);
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _problem = describeError(error, fallback: fallback);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayProvider);
    final original = widget.original;
    return ProtectDraft<void>(
      dirty: _dirty,
      busy: _busy,
      child: Form(
        key: _form,
        child: FormLayout(
          title: original == null ? 'Log weight' : 'Edit weigh-in',
          footer: ActionFooter(
            label: 'Save weight',
            onPressed: _busy || (original != null && !_dirty) ? null : _save,
            busy: _busy,
          ),
          children: [
            const SizedBox(height: Space.xl),
            LargeNumberField(
              label: 'Body weight',
              controller: _weight,
              enabled: !_busy,
              autofocus: original == null,
              onChanged: _editAmount,
              decimal: true,
              hint: '0.0',
              validator: (_) {
                final grams = _grams;
                if (grams == null || grams < 1) {
                  return 'Enter a positive weight with up to ${_unit.decimals} decimal places.';
                }
                if (grams > maxWeightGrams) {
                  return 'Enter at most ${weightText(context, maxWeightGrams, _unit)}.';
                }
                return null;
              },
            ),
            const SizedBox(height: Space.md),
            Center(
              child: _WeightUnitPicker(
                unit: _unit,
                onChanged: _busy ? null : _selectUnit,
              ),
            ),
            const SizedBox(height: Space.xl),
            RowLink(
              title: 'Date',
              detail: _day == today ? 'Today' : fullDay(_day),
              leading: const Icon(LucideIcons.calendar, size: 20),
              onTap: _busy
                  ? null
                  : () async {
                      FocusScope.of(context).unfocus();
                      final day = await pickDay(
                        context,
                        _day,
                        latest: today,
                        title: 'Weigh-in date',
                      );
                      if (mounted && day != null) setState(() => _day = day);
                    },
            ),
            FormProblem(_problem),
            if (original != null) ...[
              const SizedBox(height: Space.lg),
              QuietButton(
                'Delete weigh-in',
                _busy ? null : () => _delete(original),
                danger: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WeightUnitPicker extends StatelessWidget {
  const _WeightUnitPicker({required this.unit, required this.onChanged});

  final WeightUnit unit;
  final ValueChanged<WeightUnit>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: 'Weight unit',
      child: SegmentedButton<WeightUnit>(
        segments: [
          for (final option in WeightUnit.values)
            ButtonSegment(
              value: option,
              label: Text(option.name),
              tooltip: option.label,
            ),
        ],
        selected: {unit},
        onSelectionChanged: onChanged == null
            ? null
            : (selection) => onChanged!(selection.single),
        showSelectedIcon: false,
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(76, Space.target)),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(Space.radius)),
            ),
          ),
          side: WidgetStatePropertyAll(BorderSide(color: colors.border)),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? colors.green
                : colors.ink,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? Color.alphaBlend(
                    colors.green.withValues(alpha: .14),
                    colors.background,
                  )
                : colors.background,
          ),
        ),
      ),
    );
  }
}
