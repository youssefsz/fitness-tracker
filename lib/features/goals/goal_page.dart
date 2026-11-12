import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../shared/domain/training.dart';
import '../../shared/widgets/exercise_icon.dart';
import '../../shared/widgets/ui.dart';

Future<void> openGoal(
  BuildContext context,
  Exercise exercise,
  Goal? goal,
  Performance data,
) => Navigator.of(context).push<void>(
  platformPageRoute<void>(
    context,
    (_) => GoalPage(exercise: exercise, original: goal, data: data),
  ),
);

class GoalSummary extends StatelessWidget {
  const GoalSummary({
    required this.exercise,
    required this.goal,
    required this.data,
    required this.today,
    required this.durationStyle,
    super.key,
  });
  final Exercise exercise;
  final Goal? goal;
  final Performance data;
  final CalendarDay today;
  final DurationStyle durationStyle;

  @override
  Widget build(BuildContext context) {
    final current = goal;
    Future<void> edit() => openGoal(context, exercise, current, data);
    if (current == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            'Your goal',
            action: QuietButton('Set goal', edit, icon: LucideIcons.plus),
          ),
          Text(
            'Choose a best set you’d like to reach.',
            style: context.type.bodySmall,
          ),
        ],
      );
    }
    final status = goalStatus(current, data.days, today);
    final eligible = data.days.where(
      (d) => current.deadline == null || !d.day.isAfter(current.deadline!),
    );
    final best = eligible.fold(
      0,
      (value, day) => value > day.best ? value : day.best,
    );
    final percentage = (best / current.target).clamp(0.0, 1.0);
    String format(int number) =>
        measure(number, exercise.measurement, durationStyle);
    final statusText = switch (status) {
      GoalStatus.achieved => 'Achieved',
      GoalStatus.expired => 'Deadline passed',
      GoalStatus.pending => '${format(current.target - best)} to go',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle('Your goal', action: QuietButton('Edit goal', edit)),
        Text(
          '${measureValue(best, exercise.measurement, durationStyle)} / ${format(current.target)}',
          style: context.type.titleLarge,
        ),
        const SizedBox(height: 3),
        Text(
          current.deadline == null
              ? 'Personal best'
              : 'Best set through ${fullDay(current.deadline!)}',
          style: context.type.bodySmall,
        ),
        const SizedBox(height: 11),
        LinearProgressIndicator(
          value: percentage,
          minHeight: 7,
          borderRadius: BorderRadius.circular(20),
          backgroundColor: context.colors.border,
          semanticsLabel: 'Goal progress',
        ),
        const SizedBox(height: 7),
        Text(
          statusText,
          style: context.type.labelMedium?.copyWith(
            color: status == GoalStatus.achieved
                ? context.colors.green
                : context.colors.muted,
          ),
        ),
        if (current.deadline != null && data.best != null && data.best! > best)
          Text(
            'All-time best: ${format(data.best!)}',
            style: context.type.bodySmall,
          ),
      ],
    );
  }
}

class GoalPage extends ConsumerStatefulWidget {
  const GoalPage({
    required this.exercise,
    required this.original,
    required this.data,
    super.key,
  });
  final Exercise exercise;
  final Goal? original;
  final Performance data;

  @override
  ConsumerState<GoalPage> createState() => _GoalPageState();
}

class _GoalPageState extends ConsumerState<GoalPage> {
  late final _value = TextEditingController(
    text: widget.original?.target.toString(),
  );
  late CalendarDay? _deadline = widget.original?.deadline;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  Future<void> _pick(CalendarDay today) async {
    final limit = CalendarDay.parse('9999-12-31');
    final date = await pickDay(
      context,
      _deadline ?? today,
      latest: limit,
      title: 'Goal target date',
    );
    if (mounted && date != null) setState(() => _deadline = date);
  }

  Future<void> _save() async {
    if (_busy) return;
    final target = int.tryParse(_value.text);
    if (setValueError(target) case final error?) {
      setState(() => _error = error);
      return;
    }
    await _mutate(
      () => ref
          .read(repositoryProvider)
          .saveGoal(widget.exercise.id, target!, _deadline),
      'Goal saved.',
    );
  }

  Future<void> _remove() async {
    if (_busy) return;
    final confirmed = await confirmAction(
      context,
      title: 'Remove this goal?',
      message: 'Your exercise and all recorded sets will stay.',
      label: 'Remove goal',
      destructive: true,
    );
    if (!mounted || !confirmed) return;
    await _mutate(
      () => ref.read(repositoryProvider).removeGoal(widget.exercise.id),
      'Goal removed.',
    );
  }

  Future<void> _mutate(Future<void> Function() update, String feedback) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await update();
      if (mounted) {
        announce(context, feedback);
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final measurement = widget.exercise.measurement;
    final style = ref.watch(durationProvider);
    final today = ref.watch(todayProvider);
    final best = widget.data.best;
    final target = int.tryParse(_value.text);
    final bestByDeadline = _deadline == null
        ? best
        : widget.data.days
              .where((day) => !day.day.isAfter(_deadline!))
              .fold(0, (best, day) => day.best > best ? day.best : best);
    String format(int value) => measure(value, measurement, style);
    return ProtectDraft<void>(
      dirty:
          _value.text != (widget.original?.target.toString() ?? '') ||
          _deadline != widget.original?.deadline,
      busy: _busy,
      child: FormLayout(
        title: widget.original == null ? 'Set a goal' : 'Edit goal',
        footer: ActionFooter(
          label: 'Save goal',
          onPressed: _save,
          busy: _busy,
          secondary:
              widget.original == null ||
                  MediaQuery.viewInsetsOf(context).bottom > 0
              ? null
              : QuietButton(
                  'Remove goal',
                  _busy ? null : _remove,
                  danger: true,
                ),
        ),
        children: [
          ScreenHeading(
            widget.exercise.name,
            leading: ExerciseIcon(widget.exercise.name, size: 40),
            subtitle: 'One best-set goal',
            top: 0,
          ),
          const SizedBox(height: 10),
          const SectionTitle('Target'),
          const SizedBox(height: 10),
          TextField(
            controller: _value,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: context.type.headlineMedium,
            decoration: lineInput(
              context,
              label: 'Target in ${measurement.unit}',
              error: _error,
              suffix: measurement.unit,
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 8),
          Text(
            best == null
                ? 'No best set recorded yet.'
                : 'Your personal best is ${measure(best, measurement, style)}.',
            style: context.type.bodySmall,
          ),
          if (target != null &&
              setValueError(target) == null &&
              bestByDeadline != null) ...[
            const SizedBox(height: Space.lg),
            LinearProgressIndicator(
              value: (bestByDeadline / target).clamp(0.0, 1.0),
              minHeight: 7,
              borderRadius: BorderRadius.circular(20),
              backgroundColor: context.colors.border,
              semanticsLabel: 'Goal progress',
            ),
            const SizedBox(height: Space.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '${measureValue(bestByDeadline, measurement, style)} of ${format(target)}',
                    style: context.type.bodySmall,
                  ),
                ),
                const SizedBox(width: Space.sm),
                Flexible(
                  child: Text(
                    bestByDeadline >= target
                        ? 'Achieved'
                        : '${format(target - bestByDeadline)} to go',
                    style: context.type.bodySmall,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          const Divider(),
          SwitchListTile.adaptive(
            value: _deadline != null,
            contentPadding: EdgeInsets.zero,
            title: const Text('Target date'),
            subtitle: const Text('Optional. Leave it open-ended.'),
            onChanged: _busy
                ? null
                : (enabled) {
                    if (enabled) {
                      _pick(today);
                    } else {
                      setState(() => _deadline = null);
                    }
                  },
          ),
          if (_deadline case final date?)
            RowLink(
              title: fullDay(date),
              detail: 'Change',
              icon: LucideIcons.calendarDays,
              onTap: _busy ? null : () => _pick(today),
            ),
          const Divider(),
          const SizedBox(height: 18),
          Text(
            'The goal uses your best single set. With a target date, sets on or before that date count.',
            style: context.type.bodySmall,
          ),
        ],
      ),
    );
  }
}
