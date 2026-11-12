import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../shared/domain/training.dart';
import '../../shared/widgets/ui.dart';
import '../logging/log_page.dart';
import '../progress/performance_chart.dart';
import 'entry_row.dart';

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  late var _selected = CalendarDay.fromDate(ref.read(nowProvider)());
  late var _month = DateTime(_selected.local.year, _selected.local.month);
  String? _exercise;
  String _query = '';
  bool _searching = false;
  bool _allActivity = false;
  static const _pageSize = 20;
  int _page = 0;
  final _entryHeading = GlobalKey();

  void _goToPage(int page) {
    setState(() => _page = page);
    final heading = _entryHeading.currentContext;
    if (heading != null) Scrollable.ensureVisible(heading);
  }

  final _queryController = TextEditingController();

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  void _changeMonth(DateTime month) {
    setState(() {
      _month = month;
      _selected = CalendarDay.fromDate(month);
      _page = 0;
      _allActivity = false;
    });
  }

  void _select(CalendarDay day) {
    if (_selected != day || _allActivity) {
      ref.read(actionsProvider).select();
      setState(() {
        _selected = day;
        _allActivity = false;
        _page = 0;
      });
    }
  }

  Future<void> _jump(CalendarDay today) async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (_) => _MonthDialog(month: _month, today: today.local),
    );
    if (mounted && picked != null) _changeMonth(picked);
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayProvider);
    final filters = (
      start: CalendarDay.fromDate(_month),
      end: CalendarDay.fromDate(DateTime(_month.year, _month.month + 1, 0)),
      exercise: _exercise,
    );
    final days = calendarProvider(filters);
    final entries = entriesProvider((
      exercise: _exercise,
      day: _allActivity ? null : _selected,
      limit: _pageSize + 1,
      offset: _page * _pageSize,
      search: _query,
    ));
    return ScreenScroll(
      primary: true,
      width: 1100,
      scrollKey: const PageStorageKey('history'),
      children: [
        ScreenHeading(
          'History',
          action: RoundControl(
            _searching ? LucideIcons.x : LucideIcons.search,
            _searching ? 'Close history search' : 'Search history',
            () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                _query = '';
                _page = 0;
                _queryController.clear();
              }
            }),
          ),
        ),
        if (_searching)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SearchInput(
              controller: _queryController,
              autofocus: true,
              hint: 'Search by exercise name',
              onChanged: (value) => setState(() {
                _query = normalizeName(value);
                _page = 0;
              }),
            ),
          ),
        AsyncPanel(
          ref.watch(catalogProvider),
          retry: () => ref.invalidate(catalogProvider),
          builder: (catalog) {
            final byId = {
              for (final item in catalog) item.exercise.id: item.exercise,
            };
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FilterButton(
                  byId[_exercise]?.name ?? 'All exercises',
                  () async {
                    final filter = await chooseOption<String>(
                      context,
                      'Filter by exercise',
                      [
                        (value: '', label: 'All exercises', subtitle: null),
                        for (final item in catalog)
                          (
                            value: item.exercise.id,
                            label: item.exercise.name,
                            subtitle: item.exercise.archived
                                ? 'Archived'
                                : item.exercise.measurement.label,
                          ),
                      ],
                      selected: _exercise ?? '',
                    );
                    if (mounted && filter != null) {
                      setState(() {
                        _exercise = filter.isEmpty ? null : filter;
                        _page = 0;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                ResponsiveSplit(
                  main: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Calendar(
                        month: _month,
                        today: today,
                        selected: _selected,
                        marked: ref.watch(days).value ?? const {},
                        onChoose: () => _jump(today),
                        onSelected: _select,
                        onPrevious: _month.year == 1900 && _month.month == 1
                            ? null
                            : () => _changeMonth(
                                DateTime(_month.year, _month.month - 1),
                              ),
                        onNext:
                            DateTime(
                              _month.year,
                              _month.month + 1,
                            ).isAfter(today.local)
                            ? null
                            : () => _changeMonth(
                                DateTime(_month.year, _month.month + 1),
                              ),
                      ),
                      if (ref.watch(days).hasError)
                        QuietButton(
                          'Reload activity dates',
                          () => ref.invalidate(days),
                        ),
                      const SizedBox(height: 12),
                      const Divider(),
                    ],
                  ),
                  side: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionTitle(
                        key: _entryHeading,
                        _allActivity ? 'All activity' : weekday(_selected),
                        action: QuietButton(
                          'Add',
                          () => context.push(
                            '/log',
                            extra: LogRequest(
                              day: _allActivity ? today : _selected,
                              exercise: byId[_exercise]?.archived == false
                                  ? byId[_exercise]
                                  : null,
                            ),
                          ),
                          icon: LucideIcons.plus,
                        ),
                      ),
                      AsyncPanel(
                        ref.watch(entries),
                        retry: () => ref.invalidate(entries),
                        builder: (items) {
                          final filtered = items
                              .where(
                                (entry) => byId.containsKey(entry.exerciseId),
                              )
                              .toList();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (filtered.isEmpty)
                                EmptyBlock(
                                  title: _query.isEmpty
                                      ? 'No entries here'
                                      : 'No matches',
                                  message: _allActivity
                                      ? 'Your recorded sets will appear here.'
                                      : 'Pick another day or add a result for ${shortDay(_selected)}.',
                                ),
                              for (final entry in filtered.take(_pageSize))
                                EntryRow(
                                  key: ValueKey(entry.id),
                                  entry: entry,
                                  exercise: byId[entry.exerciseId]!,
                                  showDate: _allActivity,
                                ),
                              Wrap(
                                spacing: 8,
                                children: [
                                  if (_page > 0)
                                    QuietButton(
                                      'Newer entries',
                                      () => _goToPage(_page - 1),
                                    ),
                                  if (filtered.length > _pageSize)
                                    QuietButton(
                                      'Older entries',
                                      () => _goToPage(_page + 1),
                                    ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                      QuietButton(
                        _allActivity
                            ? 'Show selected day'
                            : 'Show all activity',
                        () => setState(() {
                          _allActivity = !_allActivity;
                          _page = 0;
                        }),
                        icon: _allActivity
                            ? LucideIcons.calendarDays
                            : LucideIcons.list,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Calendar extends StatelessWidget {
  const _Calendar({
    required this.month,
    required this.today,
    required this.selected,
    required this.marked,
    required this.onSelected,
    required this.onChoose,
    required this.onPrevious,
    required this.onNext,
  });
  final DateTime month;
  final CalendarDay today, selected;
  final Set<CalendarDay> marked;
  final ValueChanged<CalendarDay> onSelected;
  final VoidCallback onChoose;
  final VoidCallback? onPrevious, onNext;

  @override
  Widget build(BuildContext context) {
    final first = month.weekday - DateTime.monday;
    final length = DateTime(month.year, month.month + 1, 0).day;
    final cells = ((first + length) / 7).ceil() * 7;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: onChoose,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  foregroundColor: context.colors.ink,
                  alignment: Alignment.centerLeft,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        monthName(month),
                        style: context.type.titleMedium,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(LucideIcons.chevronDown, size: 15),
                  ],
                ),
              ),
            ),
            RoundControl(LucideIcons.chevronLeft, 'Previous month', onPrevious),
            RoundControl(LucideIcons.chevronRight, 'Next month', onNext),
          ],
        ),
        Row(
          children: [
            for (final (i, label) in [
              'M',
              'T',
              'W',
              'T',
              'F',
              'S',
              'S',
            ].indexed)
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: context.type.bodySmall,
                    semanticsLabel: [
                      'Monday',
                      'Tuesday',
                      'Wednesday',
                      'Thursday',
                      'Friday',
                      'Saturday',
                      'Sunday',
                    ][i],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var row = 0; row < cells ~/ 7; row++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(
                  child: _cell(context, row * 7 + col - first + 1, length),
                ),
            ],
          ),
      ],
    );
  }

  Widget _cell(BuildContext context, int num, int length) {
    if (num < 1 || num > length) return const SizedBox(height: 46);
    final day = CalendarDay.fromDate(DateTime(month.year, month.month, num));
    final active = selected == day, hasEntries = marked.contains(day);
    final enabled = !day.isAfter(today);
    return Semantics(
      selected: active,
      button: true,
      enabled: enabled,
      label: '${fullDay(day)}${hasEntries ? ', has records' : ''}',
      child: InkWell(
        onTap: enabled ? () => onSelected(day) : null,
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          height: 46,
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: Container(
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? context.colors.pill : Colors.transparent,
                ),
                child: ExcludeSemantics(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '$num',
                            style: context.type.labelLarge?.copyWith(
                              color: active
                                  ? context.colors.onPill
                                  : enabled
                                  ? context.colors.ink
                                  : context.colors.muted.withValues(alpha: .64),
                            ),
                          ),
                        ),
                      ),
                      if (hasEntries)
                        Positioned(
                          bottom: 3,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: active
                                  ? context.colors.onPill
                                  : context.colors.green,
                            ),
                            child: const SizedBox.square(dimension: 4),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthDialog extends StatefulWidget {
  const _MonthDialog({required this.month, required this.today});
  final DateTime month, today;

  @override
  State<_MonthDialog> createState() => _MonthDialogState();
}

class _MonthDialogState extends State<_MonthDialog> {
  late var _year = widget.month.year;
  late var _month = widget.month.month;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Jump to month'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<int>(
          initialValue: _year,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Year'),
          items: [
            for (var y = widget.today.year; y >= 1900; y--)
              DropdownMenuItem(value: y, child: Text('$y')),
          ],
          onChanged: (y) {
            if (y == null) return;
            setState(() {
              _year = y;
              if (_year == widget.today.year && _month > widget.today.month) {
                _month = widget.today.month;
              }
            });
          },
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<int>(
          key: ValueKey(_year),
          initialValue: _month,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Month'),
          items: [
            for (
              var m = 1;
              m <= (_year == widget.today.year ? widget.today.month : 12);
              m++
            )
              DropdownMenuItem(
                value: m,
                child: Text(
                  MaterialLocalizations.of(context)
                      .formatMonthYear(DateTime(_year, m))
                      .replaceFirst(' $_year', ''),
                ),
              ),
          ],
          onChanged: (m) {
            if (m != null) setState(() => _month = m);
          },
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, DateTime(_year, _month)),
        child: const Text('Show month'),
      ),
    ],
  );
}
