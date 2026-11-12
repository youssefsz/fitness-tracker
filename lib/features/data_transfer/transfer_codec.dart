import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../shared/domain/training.dart';

const backupFormat = 'fitness-backup';
const activityFormat = 'fitness-activity-import';
const transferVersion = 1;
const maxTransferBytes = 20 * 1024 * 1024;
const maxTransferEntries = 20000;
const maxTransferSets = 100000;
const maxTransferExercises = 3000;
const maxTransferReceipts = 20000;
const _pretty = JsonEncoder.withIndent('  ');

class ActivityRecord {
  ActivityRecord(
    this.day,
    this.name,
    this.measurement,
    Iterable<int> sets,
    this.notes,
  ) : sets = List.unmodifiable(sets);
  final CalendarDay day;
  final String name;
  final Measurement measurement;
  final List<int> sets;
  final String? notes;

  String get key => activityKey(name, measurement);
}

String activityKey(String name, Measurement type) =>
    '${type.name}:${normalizeName(name)}';

class ActivityBatch {
  ActivityBatch(Iterable<ActivityRecord> records)
    : records = List.unmodifiable(records);

  final List<ActivityRecord> records;
  late final String fingerprint = _hash([
    activityFormat,
    transferVersion,
    for (final r in records) [r.day.iso, r.key, r.sets, r.notes],
  ]);
}

String _hash(Object value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();

class _Field {
  const _Field(this.value, [this.path = 'JSON']);
  final Object? value;
  final String path;
  Never fail(String message) => throw FormatException('$path: $message');

  Map<String, Object?> object(
    List<String> keys, {
    List<String> optional = const [],
  }) {
    final data = value;
    if (data is! Map<String, Object?>) fail('Expected an object.');
    for (final key in data.keys) {
      if (!keys.contains(key) && !optional.contains(key)) {
        fail('Unexpected field "$key".');
      }
    }
    for (final key in keys) {
      if (!data.containsKey(key)) fail('Missing field "$key".');
    }
    return data;
  }

  _Field get(String key) =>
      _Field((value as Map<String, Object?>)[key], '$path.$key');

  List<_Field> list({required int limit, int min = 0}) {
    final data = value;
    if (data is! List<Object?>) fail('Expected an array.');
    if (data.length < min || data.length > limit) {
      fail('Use $min to $limit items.');
    }
    return [
      for (final (i, item) in data.indexed) _Field(item, '$path[${i + 1}]'),
    ];
  }

  String string({int min = 1, int max = 80}) {
    final data = value;
    if (data is! String || data.length < min || data.length > max) {
      fail('Expected text with $min to $max characters.');
    }
    return data;
  }

  String identifier() {
    final id = string();
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]*$').hasMatch(id)) {
      fail('Invalid record ID.');
    }
    return id;
  }

  String name() {
    final name = string(max: 256);
    if (exerciseNameError(name) case final error?) fail(error);
    return name.trim();
  }

  String? notes({bool trim = true}) {
    if (value == null) return null;
    final raw = string(min: 0, max: maxNotes);
    return trim ? (raw.trim().isEmpty ? null : raw.trim()) : raw;
  }

  int integer(int min, int max) {
    final data = value;
    if (data is! int || data < min || data > max) {
      fail('Expected a whole number from $min to $max.');
    }
    return data;
  }

  bool boolean() =>
      value is bool ? value as bool : fail('Expected true or false.');

  T choice<T extends Enum>(List<T> choices) {
    for (final choice in choices) {
      if (value == choice.name) return choice;
    }
    fail('Use one of: ${choices.map((c) => c.name).join(', ')}.');
  }

  CalendarDay day({CalendarDay? today}) {
    final raw = string(min: 10, max: 10);
    late final CalendarDay date;
    try {
      date = CalendarDay.parse(raw);
    } on FormatException catch (e) {
      fail(e.message);
    }
    if (today != null && date.isAfter(today)) {
      fail('Activity cannot be dated in the future.');
    }
    return date;
  }

  DateTime timestamp() {
    final input = string(max: 40);
    final valid = RegExp(
      r'^\d{4}-\d{2}-\d{2}T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d{1,6})?Z$',
    );
    final date = DateTime.tryParse(input);
    if (date == null ||
        !valid.hasMatch(input) ||
        CalendarDay.fromDate(date).iso != input.substring(0, 10)) {
      fail('Expected a valid ISO 8601 UTC timestamp ending in Z.');
    }
    return date;
  }
}

_Field _root(String text, String format, List<String> fields) {
  if (text.length > maxTransferBytes ||
      utf8.encode(text).length > maxTransferBytes) {
    throw const FormatException(
      'JSON is larger than 20 MB. Choose a smaller file.',
    );
  }
  final root = _Field(
    jsonDecode(text.startsWith('\uFEFF') ? text.substring(1) : text),
  );
  if (root.value case {'format': final String actual} when actual != format) {
    throw FormatException('This is $actual. Expected $format.');
  }
  if (root.value case {'schemaVersion': final int version}
      when version != transferVersion) {
    throw FormatException(
      'Version $version is not supported. This app reads version $transferVersion.',
    );
  }
  root.object(['format', 'schemaVersion', ...fields]);
  if (root.get('format').value != format) {
    root.get('format').fail('Expected "$format".');
  }
  if (root.get('schemaVersion').value is! int) {
    root.get('schemaVersion').fail('Expected an integer version.');
  }
  return root;
}

ActivityBatch decodeActivity(String text, CalendarDay today) {
  final root = _root(text, activityFormat, ['records']);
  var count = 0;
  final records = <ActivityRecord>[];
  for (final row
      in root.get('records').list(limit: maxTransferEntries, min: 1)) {
    row.object(['date', 'exercise', 'sets', 'notes']);
    final exercise = row.get('exercise')..object(['name', 'measurement']);
    final sets = row.get('sets').list(limit: maxSetsPerEntry, min: 1);
    count += sets.length;
    if (count > maxTransferSets) {
      row.fail('The file contains more than $maxTransferSets sets.');
    }
    records.add(
      ActivityRecord(
        row.get('date').day(today: today),
        exercise.get('name').name(),
        exercise.get('measurement').choice(Measurement.values),
        sets.map((s) => s.integer(1, maxSetValue)),
        row.get('notes').notes(),
      ),
    );
  }
  if (records.map((r) => r.key).toSet().length > maxTransferExercises) {
    throw const FormatException(
      'The file contains more than $maxTransferExercises exercises.',
    );
  }
  return ActivityBatch(records);
}

Map<String, Object?> _exerciseJson(Exercise x) => {
  'id': x.id,
  'name': x.name,
  'measurement': x.measurement.name,
  'archived': x.archived,
  'createdAt': x.createdAt.toUtc().toIso8601String(),
  'updatedAt': x.updatedAt.toUtc().toIso8601String(),
};
Map<String, Object?> _entryJson(Entry e, {bool includeOrder = true}) => {
  'id': e.id,
  'exerciseId': e.exerciseId,
  'date': e.day.iso,
  'notes': e.notes,
  if (includeOrder) 'order': e.order,
  'createdAt': e.createdAt.toUtc().toIso8601String(),
  'updatedAt': e.updatedAt.toUtc().toIso8601String(),
  'sets': [
    for (final s in e.sets)
      {'id': s.id, 'position': s.position, 'value': s.value},
  ],
};
Map<String, Object?> _goalJson(Goal g) => {
  'exerciseId': g.exerciseId,
  'target': g.target,
  'deadline': g.deadline?.iso,
  'updatedAt': g.updatedAt.toUtc().toIso8601String(),
};

String exerciseContent(Exercise value) => jsonEncode(_exerciseJson(value));
String entryContent(Entry value) =>
    jsonEncode(_entryJson(value, includeOrder: false));
String goalContent(Goal value) => jsonEncode(_goalJson(value));

Map<String, Object?> _backupJson(BackupData data) => {
  'exercises': [
    for (final x
        in (data.exercises.toList()..sort((a, b) => a.id.compareTo(b.id))))
      _exerciseJson(x),
  ],
  'entries': [
    for (final e
        in (data.entries.toList()..sort((a, b) => a.order.compareTo(b.order))))
      _entryJson(e),
  ],
  'goals': [
    for (final g
        in (data.goals.toList()
          ..sort((a, b) => a.exerciseId.compareTo(b.exerciseId))))
      _goalJson(g),
  ],
  'settings': {
    'appearance': data.preferences.appearance.name,
    'duration': data.preferences.duration.name,
    'haptics': data.preferences.haptics,
  },
  'importReceipts': [
    for (final id in (data.receipts.keys.toList()..sort()))
      {
        'fingerprint': id,
        'importedAt': data.receipts[id]!.toUtc().toIso8601String(),
      },
  ],
};

String backupFingerprint(BackupData data) => _hash(_backupJson(data));

String encodeBackup(BackupData data, DateTime exportedAt) => _pretty.convert({
  'format': backupFormat,
  'schemaVersion': transferVersion,
  'exportedAt': exportedAt.toUtc().toIso8601String(),
  ..._backupJson(data),
});

BackupData decodeBackup(String text, CalendarDay today) {
  final root = _root(text, backupFormat, [
    'exportedAt',
    'exercises',
    'entries',
    'goals',
    'settings',
    'importReceipts',
  ]);
  root.get('exportedAt').timestamp();
  final ids = <String>{}, names = <String>{};
  final exercises = <Exercise>[];
  for (final row in root.get('exercises').list(limit: maxTransferExercises)) {
    row.object([
      'id',
      'name',
      'measurement',
      'archived',
      'createdAt',
      'updatedAt',
    ]);
    final id = row.get('id').identifier();
    final name = row.get('name').name();
    if (!ids.add(id)) row.get('id').fail('Duplicate exercise ID.');
    if (!names.add(normalizeName(name))) {
      row.get('name').fail('Duplicate exercise name.');
    }
    final created = row.get('createdAt').timestamp(),
        updated = row.get('updatedAt').timestamp();
    if (updated.isBefore(created)) {
      row.get('updatedAt').fail('Cannot be before creation.');
    }
    exercises.add(
      Exercise(
        id: id,
        name: name,
        measurement: row.get('measurement').choice(Measurement.values),
        archived: row.get('archived').boolean(),
        createdAt: created,
        updatedAt: updated,
      ),
    );
  }
  final entryIds = <String>{}, setIds = <String>{};
  final orders = <int>{};
  final entries = <Entry>[];
  for (final row in root.get('entries').list(limit: maxTransferEntries)) {
    row.object([
      'id',
      'exerciseId',
      'date',
      'notes',
      'order',
      'createdAt',
      'updatedAt',
      'sets',
    ]);
    final id = row.get('id').identifier();
    final exerciseId = row.get('exerciseId').identifier();
    final order = row.get('order').integer(1, maxEntryOrder);
    if (!entryIds.add(id)) row.get('id').fail('Duplicate entry ID.');
    if (!ids.contains(exerciseId)) {
      row.get('exerciseId').fail('Unknown exercise ID.');
    }
    if (!orders.add(order)) row.get('order').fail('Duplicate entry order.');
    final sets = <RecordedSet>[];
    final positions = <int>{};
    for (final set in row.get('sets').list(limit: maxSetsPerEntry, min: 1)) {
      set.object(['id', 'position', 'value']);
      final setId = set.get('id').identifier();
      final position = set.get('position').integer(0, maxSetsPerEntry - 1);
      if (!setIds.add(setId)) set.get('id').fail('Duplicate set ID.');
      if (!positions.add(position)) {
        set.get('position').fail('Duplicate set position.');
      }
      sets.add((
        id: setId,
        position: position,
        value: set.get('value').integer(1, maxSetValue),
      ));
    }
    if (setIds.length > maxTransferSets) {
      row.fail('The backup contains more than $maxTransferSets sets.');
    }
    sets.sort((a, b) => a.position.compareTo(b.position));
    if (sets.last.position != sets.length - 1) {
      row.get('sets').fail('Set positions must be contiguous from 0.');
    }
    final created = row.get('createdAt').timestamp(),
        updated = row.get('updatedAt').timestamp();
    if (updated.isBefore(created)) {
      row.get('updatedAt').fail('Cannot be before creation.');
    }
    entries.add(
      Entry(
        id: id,
        exerciseId: exerciseId,
        day: row.get('date').day(today: today),
        notes: row.get('notes').notes(trim: false),
        order: order,
        createdAt: created,
        updatedAt: updated,
        sets: sets,
      ),
    );
  }
  final goalIds = <String>{};
  final goals = <Goal>[];
  for (final row in root.get('goals').list(limit: maxTransferExercises)) {
    row.object(['exerciseId', 'target', 'deadline', 'updatedAt']);
    final id = row.get('exerciseId').identifier();
    if (!ids.contains(id)) row.get('exerciseId').fail('Unknown exercise ID.');
    if (!goalIds.add(id)) {
      row.get('exerciseId').fail('Only one goal is allowed for each exercise.');
    }
    goals.add(
      Goal(
        exerciseId: id,
        target: row.get('target').integer(1, maxSetValue),
        deadline: row.get('deadline').value == null
            ? null
            : row.get('deadline').day(),
        updatedAt: row.get('updatedAt').timestamp(),
      ),
    );
  }
  final settings = root.get('settings')
    ..object(['appearance', 'duration', 'haptics']);
  final receipts = <String, DateTime>{};
  for (final row
      in root.get('importReceipts').list(limit: maxTransferReceipts)) {
    row.object(['fingerprint', 'importedAt']);
    final hash = row.get('fingerprint').string(min: 64, max: 64);
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      row.get('fingerprint').fail('Invalid receipt fingerprint.');
    }
    if (receipts.containsKey(hash)) {
      row.get('fingerprint').fail('Duplicate receipt.');
    }
    receipts[hash] = row.get('importedAt').timestamp();
  }
  return BackupData(
    exercises: exercises,
    entries: entries,
    goals: goals,
    receipts: receipts,
    preferences: (
      appearance: settings.get('appearance').choice(Appearance.values),
      duration: settings.get('duration').choice(DurationStyle.values),
      haptics: settings.get('haptics').boolean(),
    ),
  );
}

String activityExample(CalendarDay today) => _pretty.convert({
  'format': activityFormat,
  'schemaVersion': transferVersion,
  'records': [
    {
      'date': today.iso,
      'exercise': {
        'name': 'Push-ups',
        'measurement': Measurement.repetitions.name,
      },
      'sets': [22, 20, 18],
      'notes': null,
    },
    {
      'date': today.iso,
      'exercise': {'name': 'Plank', 'measurement': Measurement.duration.name},
      'sets': [100, 90],
      'notes': null,
    },
  ],
});

String aiPrompt(DateTime localNow, {List<Exercise> catalog = const []}) {
  final day = CalendarDay.fromDate(localNow);
  final offset = localNow.timeZoneOffset.inMinutes;
  final utc =
      '${offset < 0 ? '-' : '+'}${(offset.abs() ~/ 60).toString().padLeft(2, '0')}:'
      '${(offset.abs() % 60).toString().padLeft(2, '0')}';
  return '''
You are converting exercise history explicitly supplied by the user into JSON for a fitness tracker.

Return the $activityFormat version $transferVersion format shown below.

Current local date: ${day.iso}. Local time zone: ${localNow.timeZoneName} (UTC$utc).
Only include activity the user actually reported completing. Do not invent exercises, dates, set breakdowns, values, personal records, or goals.

Use YYYY-MM-DD activity dates. Resolve relative dates from the relevant message context. Do not reinterpret every historical "today" as the current date. If a date or essential value cannot be determined, ask a concise clarification question before producing the final JSON.

Use measurement "repetitions" for repetition counts and "duration" for timed activity. Store timed sets as positive whole seconds. Every set is a whole number from 1 to $maxSetValue, and each entry needs 1 to $maxSetsPerEntry sets.

Preserve the order in which sets were reported. For example, three sets of ten may become [10, 10, 10]. A statement of thirty total repetitions does not establish three sets of ten; ask for the missing breakdown where necessary.

Preserve separate entries and genuine repeated sets. Preserve decreases in performance.

Use notes only for information supplied by the user, or null. Do not generate database IDs or calculated progress statistics.

When all required information is clear, output one valid JSON object only, without Markdown fences, comments, or surrounding explanation. The following is a format example only. Do not copy example activity into the user's records.
${catalog.isEmpty ? '' : '\nOptional existing exercise names and units (reference only):\n${jsonEncode(catalog.map((x) => {'name': x.name, 'measurement': x.measurement.name}).toList())}\n'}
${activityExample(day)}
''';
}

String encodeCsv(BackupData data) {
  final byId = {for (final x in data.exercises) x.id: x};
  final entries = data.entries.toList()
    ..sort((a, b) {
      final day = a.day.compareTo(b.day);
      return day == 0 ? a.order.compareTo(b.order) : day;
    });
  final out = StringBuffer(
    'date,exercise,measurement,unit,entry_id,set_id,set_number,value,notes,created_at_utc,updated_at_utc\r\n',
  );
  String csv(String text, {bool userText = false}) {
    if (userText && RegExp(r'^(?:[\t\r\n]|\s*[=+\-@＝＋－＠])').hasMatch(text)) {
      text = "'$text";
    }
    return '"${text.replaceAll('"', '""')}"';
  }

  for (final e in entries) {
    final x = byId[e.exerciseId]!;
    for (final s in e.sets) {
      out.writeln(
        [
          e.day.iso,
          csv(x.name, userText: true),
          x.measurement.name,
          x.measurement.unit,
          csv(e.id),
          csv(s.id),
          s.position + 1,
          s.value,
          csv(e.notes ?? '', userText: true),
          e.createdAt.toUtc().toIso8601String(),
          '${e.updatedAt.toUtc().toIso8601String()}\r',
        ].join(','),
      );
    }
  }
  return out.toString();
}
