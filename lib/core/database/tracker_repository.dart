import 'dart:async';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../shared/domain/body_metrics.dart';
import '../../shared/domain/training.dart';
import 'database.dart' hide Entry;

typedef OverviewExercise = ({
  String exerciseId,
  int first,
  int latest,
  int best,
  int count,
  CalendarDay firstDay,
  CalendarDay latestDay,
  List<DailyResult> trend,
});

typedef OverviewData = ({
  List<OverviewExercise> exercises,
  CalendarDay? firstDay,
  List<Entry> recent,
});

typedef CatalogItem = ({
  Exercise exercise,
  int count,
  CalendarDay? lastDay,
  int? latest,
  bool hasGoal,
});

class TrackerRepository {
  TrackerRepository(this.db, {DateTime Function()? now, String Function()? id})
    : now = now ?? DateTime.now,
      newId = id ?? const Uuid().v4;

  final TrackerDatabase db;
  final DateTime Function() now;
  final String Function() newId;
  String get _timestamp => now().toUtc().toIso8601String();

  String _timestampAfter(String previous) {
    final time = now().toUtc();
    final last = DateTime.parse(previous);
    return (time.isAfter(last)
            ? time
            : last.add(const Duration(microseconds: 1)))
        .toIso8601String();
  }

  Future<void> open() async {
    await db.select(db.appPreferences).get();
  }

  Future<void> close() => db.close();

  Exercise _exercise(ExerciseRow row) => Exercise(
    id: row.id,
    name: row.name,
    measurement: Measurement.values.byName(row.measurement),
    trackSets: row.trackSets,
    archived: row.archived,
    createdAt: DateTime.parse(row.createdAt),
    updatedAt: DateTime.parse(row.updatedAt),
  );

  CalendarDay? _optionalDay(String? value) =>
      value == null ? null : CalendarDay.parse(value);

  Goal _goal(GoalRow row) => Goal(
    exerciseId: row.exerciseId,
    target: row.target,
    deadline: row.deadline == null ? null : CalendarDay.parse(row.deadline!),
    updatedAt: DateTime.parse(row.updatedAt),
  );

  Preferences _preferences(AppPreference? row) => row == null
      ? defaultPreferences
      : (
          appearance: Appearance.values.byName(row.appearance),
          duration: DurationStyle.values.byName(row.durationStyle),
          haptics: row.haptics,
        );

  Stream<Preferences> watchPreferences() => db
      .select(db.appPreferences)
      .watchSingleOrNull()
      .map(_preferences)
      .distinct();

  Future<void> savePreferences(Preferences value) => db
      .into(db.appPreferences)
      .insertOnConflictUpdate(
        AppPreferencesCompanion.insert(
          id: const Value(1),
          appearance: value.appearance.name,
          durationStyle: value.duration.name,
          haptics: value.haptics,
        ),
      );

  Stream<String?> watchProgressExercise() => db
      .select(db.appPreferences)
      .watchSingleOrNull()
      .map((row) => row?.progressExerciseId)
      .distinct();

  Future<void> saveProgressExercise(String id) => db
      .into(db.appPreferences)
      .insert(
        AppPreferencesCompanion.insert(
          id: const Value(1),
          appearance: defaultPreferences.appearance.name,
          durationStyle: defaultPreferences.duration.name,
          haptics: defaultPreferences.haptics,
          progressExerciseId: Value(id),
        ),
        onConflict: DoUpdate(
          (_) => AppPreferencesCompanion(progressExerciseId: Value(id)),
        ),
      );

  ProfileDetails _profileDetails({
    String? name,
    int? height,
    String? heightUnit,
    String? weightUnit,
  }) => (
    displayName: name,
    heightMillimeters: height,
    heightUnit: heightUnit == null
        ? defaultProfileDetails.heightUnit
        : HeightUnit.values.byName(heightUnit),
    weightUnit: weightUnit == null
        ? defaultProfileDetails.weightUnit
        : WeightUnit.values.byName(weightUnit),
  );

  Stream<LocalProfile> watchProfile() => db
      .select(db.localProfiles)
      .watchSingleOrNull()
      .map(
        (row) => LocalProfile(
          _profileDetails(
            name: row?.displayName,
            height: row?.heightMillimeters,
            heightUnit: row?.heightUnit,
            weightUnit: row?.weightUnit,
          ),
          row?.photo,
          row == null
              ? AvatarPreset.anonymous
              : AvatarPreset.values.byName(row.avatarPreset),
        ),
      );

  Future<void> saveProfileDetails(ProfileDetails details) async {
    final name = details.displayName?.trim();
    final height = details.heightMillimeters;
    if (displayNameError(name ?? '') case final error?) {
      throw TrackerException(error);
    }
    if (height != null && (height < 1 || height > maxHeightMillimeters)) {
      throw const TrackerException('Enter a height from 0.1 to 300 cm.');
    }
    await db
        .into(db.localProfiles)
        .insertOnConflictUpdate(
          LocalProfilesCompanion(
            id: const Value(1),
            displayName: Value(name == null || name.isEmpty ? null : name),
            heightMillimeters: Value(height),
            heightUnit: Value(details.heightUnit.name),
            weightUnit: Value(details.weightUnit.name),
          ),
        );
  }

  Future<void> saveProfilePhoto(Uint8List? photo) async {
    if (photo != null &&
        (photo.isEmpty || photo.length > maxProfilePhotoBytes)) {
      throw const TrackerException('Choose a smaller photo.');
    }
    await db
        .into(db.localProfiles)
        .insertOnConflictUpdate(
          LocalProfilesCompanion(id: const Value(1), photo: Value(photo)),
        );
  }

  Future<void> saveProfileAvatar(AvatarPreset preset) => db
      .into(db.localProfiles)
      .insertOnConflictUpdate(
        LocalProfilesCompanion(
          id: const Value(1),
          avatarPreset: Value(preset.name),
          photo: const Value(null),
        ),
      );

  WeighIn _weighIn(WeighInRow row) =>
      (day: CalendarDay.parse(row.day), grams: row.grams);

  Stream<List<WeighIn>> watchWeighIns({int? limit, CalendarDay? since}) {
    final query = db.select(db.weighIns)
      ..orderBy([(row) => OrderingTerm.desc(row.day)]);
    if (since != null) {
      query.where((row) => row.day.isBiggerOrEqualValue(since.iso));
    }
    if (limit != null) query.limit(limit);
    return query.watch().map((rows) => rows.map(_weighIn).toList());
  }

  Future<void> saveWeighIn(
    WeighIn value, {
    WeighIn? original,
    WeightUnit? displayUnit,
  }) => db.transaction(() async {
    if (value.day.isBefore(CalendarDay.earliest) ||
        value.day.isAfter(CalendarDay.fromDate(now()))) {
      throw const TrackerException('Choose today or an earlier date.');
    }
    if (value.grams < 1 || value.grams > maxWeightGrams) {
      throw const TrackerException(
        'Enter a weight above zero and at most 1,000 kg.',
      );
    }
    if (original == null || original.day != value.day) {
      final existing = await (db.select(
        db.weighIns,
      )..where((row) => row.day.equals(value.day.iso))).getSingleOrNull();
      if (existing != null) {
        throw const TrackerException(
          'A weight is already logged for that date. Edit it in weight history.',
        );
      }
    }
    if (original != null) await deleteWeighIn(original);
    await db
        .into(db.weighIns)
        .insert(
          WeighInsCompanion.insert(day: value.day.iso, grams: value.grams),
        );
    if (displayUnit != null) {
      await db
          .into(db.localProfiles)
          .insertOnConflictUpdate(
            LocalProfilesCompanion(
              id: const Value(1),
              weightUnit: Value(displayUnit.name),
            ),
          );
    }
  });

  Future<void> deleteWeighIn(WeighIn original) async {
    final deleted =
        await (db.delete(db.weighIns)..where(
              (row) =>
                  row.day.equals(original.day.iso) &
                  row.grams.equals(original.grams),
            ))
            .go();
    if (deleted == 0) {
      throw const TrackerException(
        'This entry changed. Reopen it from weight history.',
      );
    }
  }

  Future<BodyData> _bodySnapshot() async {
    final table = db.localProfiles;
    final row =
        await (db.selectOnly(table)..addColumns([
              table.displayName,
              table.heightMillimeters,
              table.heightUnit,
              table.weightUnit,
            ]))
            .getSingleOrNull();
    return BodyData(
      _profileDetails(
        name: row?.read(table.displayName),
        height: row?.read(table.heightMillimeters),
        heightUnit: row?.read(table.heightUnit),
        weightUnit: row?.read(table.weightUnit),
      ),
      (await (db.select(
        db.weighIns,
      )..orderBy([(row) => OrderingTerm.asc(row.day)])).get()).map(_weighIn),
    );
  }

  Stream<List<CatalogItem>> watchCatalog() => db
      .customSelect(
        '''
    WITH totals AS (
      SELECT e.exercise_id, COUNT(*) AS set_count
      FROM entries e JOIN exercise_sets s ON s.entry_id = e.id
      GROUP BY e.exercise_id
    )
    SELECT x.*, coalesce(t.set_count, 0) AS set_count,
      EXISTS(SELECT 1 FROM goals g WHERE g.exercise_id=x.id) AS has_goal,
      (SELECT e.activity_date FROM entries e WHERE e.exercise_id=x.id
        ORDER BY e.activity_date DESC, e.entry_order DESC LIMIT 1) AS last_day,
      (SELECT s.value FROM entries e JOIN exercise_sets s ON s.entry_id=e.id
        WHERE e.exercise_id=x.id
        ORDER BY e.activity_date DESC, e.entry_order DESC, s.position DESC LIMIT 1) AS latest
    FROM exercises x LEFT JOIN totals t ON t.exercise_id=x.id
    ORDER BY x.normalized_name
    ''',
        readsFrom: {db.exercises, db.entries, db.exerciseSets, db.goals},
      )
      .watch()
      .map(
        (rows) => List.unmodifiable(
          rows.map(
            (r) => (
              exercise: _exercise(db.exercises.map(r.data)),
              count: r.read<int>('set_count'),
              lastDay: _optionalDay(r.readNullable<String>('last_day')),
              latest: r.readNullable<int>('latest'),
              hasGoal: r.read<int>('has_goal') != 0,
            ),
          ),
        ),
      );

  Future<Exercise> createExercise(
    String name,
    Measurement measurement, {
    bool trackSets = false,
  }) => db.transaction(
    () => _createExercise(name, measurement, trackSets: trackSets),
  );

  Future<Exercise> _createExercise(
    String name,
    Measurement measurement, {
    required bool trackSets,
  }) async {
    final clean = await _checkName(name);
    final time = _timestamp;
    final id = newId();
    final row = await db
        .into(db.exercises)
        .insertReturning(
          ExercisesCompanion.insert(
            id: id,
            name: clean,
            normalizedName: normalizeName(clean),
            measurement: measurement.name,
            trackSets: Value(trackSets),
            createdAt: time,
            updatedAt: time,
          ),
        );
    return _exercise(row);
  }

  Future<String> _checkName(String name, {String? except}) async {
    if (exerciseNameError(name) case final error?) {
      throw TrackerException(error);
    }
    final clean = name.trim();
    final existing =
        await (db.select(db.exercises)
              ..where((x) => x.normalizedName.equals(normalizeName(clean))))
            .getSingleOrNull();
    if (existing != null && existing.id != except) {
      throw TrackerException(
        existing.archived
            ? 'That name belongs to an archived exercise. Restore it or choose another name.'
            : 'An exercise already uses that name.',
      );
    }
    return clean;
  }

  Future<void> editExercise(
    String id,
    String name,
    Measurement measurement, {
    bool? trackSets,
  }) => db.transaction(() async {
    final existing = await _findExercise(id);
    final clean = await _checkName(name, except: id);
    if (existing.measurement != measurement.name) {
      final hasGoal = await (db.select(
        db.goals,
      )..where((g) => g.exerciseId.equals(id))).getSingleOrNull();
      if (hasGoal != null || await _hasEntries(id)) {
        throw const TrackerException(
          'Remove the goal and recorded history before changing the measurement.',
        );
      }
    }
    await (db.update(db.exercises)..where((x) => x.id.equals(id))).write(
      ExercisesCompanion(
        name: Value(clean),
        normalizedName: Value(normalizeName(clean)),
        measurement: Value(measurement.name),
        trackSets: trackSets == null ? const Value.absent() : Value(trackSets),
        updatedAt: Value(_timestampAfter(existing.updatedAt)),
      ),
    );
  });

  Future<ExerciseRow> _findExercise(String id) async =>
      await (db.select(
        db.exercises,
      )..where((x) => x.id.equals(id))).getSingleOrNull() ??
      (throw const TrackerException('This exercise no longer exists.'));

  Future<bool> _hasEntries(String id) async =>
      await (db.select(db.entries)
            ..where((entry) => entry.exerciseId.equals(id))
            ..limit(1))
          .getSingleOrNull() !=
      null;

  Future<void> deleteExercise(String id) => db.transaction(() async {
    await (db.delete(
      db.entries,
    )..where((entry) => entry.exerciseId.equals(id))).go();
    await (db.delete(
      db.exercises,
    )..where((exercise) => exercise.id.equals(id))).go();
  });

  Future<void> deleteAllExercises() => db.transaction(_clearExercises);

  Future<void> resetAllData() => db.transaction(() async {
    await _clearExercises();
    await db.delete(db.weighIns).go();
    await db.delete(db.localProfiles).go();
    await db.delete(db.appPreferences).go();
  });

  Future<void> _clearExercises() async {
    await db.delete(db.exerciseSets).go();
    await db.delete(db.entries).go();
    await db.delete(db.goals).go();
    await db.delete(db.exercises).go();
    await db.delete(db.importReceipts).go();
  }

  Future<void> setArchived(String id, bool archived) =>
      db.transaction(() async {
        final existing = await _findExercise(id);
        if (existing.archived == archived) return;
        await (db.update(db.exercises)..where((x) => x.id.equals(id))).write(
          ExercisesCompanion(
            archived: Value(archived),
            updatedAt: Value(_timestampAfter(existing.updatedAt)),
          ),
        );
      });

  void _validateDraft(EntryDraft draft, Measurement measurement) {
    if (draft.day.isBefore(CalendarDay.earliest) ||
        draft.day.isAfter(CalendarDay.fromDate(now()))) {
      throw const TrackerException('Choose today or a past activity date.');
    }
    if ((draft.notes?.length ?? 0) > maxNotes) {
      throw const TrackerException('Notes are too long.');
    }
    if (draft.sets.isEmpty || draft.sets.length > maxSetsPerEntry) {
      throw const TrackerException('Each entry needs between 1 and 100 sets.');
    }
    if (draft.sets.any(
      (s) =>
          exerciseValueError(s.value, measurement) != null ||
          !validSetReps(s.reps, measurement),
    )) {
      throw const TrackerException('Correct the invalid set values.');
    }
  }

  Future<int> _nextOrder() async =>
      (await db
              .customSelect(
                'SELECT coalesce(max(entry_order), 0) + 1 AS next FROM entries',
              )
              .getSingle())
          .read<int>('next');

  Future<void> log(List<EntryDraft> drafts) => db.transaction(() async {
    if (drafts.isEmpty) throw const TrackerException('Add an exercise first.');
    final ids = drafts.map((d) => d.exerciseId).toSet();
    final exercises = await (db.select(
      db.exercises,
    )..where((x) => x.id.isIn(ids))).get();
    if (exercises.length != ids.length || exercises.any((e) => e.archived)) {
      throw const TrackerException(
        'An exercise is missing or archived. Check your selections.',
      );
    }
    await _insertDrafts(drafts, {
      for (final e in exercises) e.id: Measurement.values.byName(e.measurement),
    });
  });

  Future<void> _insertDrafts(
    List<EntryDraft> drafts,
    Map<String, Measurement> measurements,
  ) async {
    for (final draft in drafts) {
      final measurement = measurements[draft.exerciseId];
      if (measurement == null) {
        throw const TrackerException('This exercise no longer exists.');
      }
      _validateDraft(draft, measurement);
    }
    var order = await _nextOrder();
    if (order + drafts.length - 1 > maxEntryOrder) {
      throw const TrackerException(
        'No more entry order numbers are available.',
      );
    }
    final timestamp = _timestamp;
    final entries = <EntriesCompanion>[];
    final sets = <ExerciseSetsCompanion>[];
    for (final draft in drafts) {
      final id = newId();
      entries.add(
        EntriesCompanion.insert(
          id: id,
          exerciseId: draft.exerciseId,
          activityDate: draft.day.iso,
          notes: Value(_cleanNotes(draft.notes)),
          entryOrder: order++,
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );
      for (final (i, set) in draft.sets.indexed) {
        sets.add(
          ExerciseSetsCompanion.insert(
            id: newId(),
            entryId: id,
            position: i,
            value: set.value,
            reps: Value(set.reps),
          ),
        );
      }
    }
    await db.batch((b) {
      b.insertAll(db.entries, entries);
      b.insertAll(db.exerciseSets, sets);
    });
  }

  String? _cleanNotes(String? notes) =>
      notes == null || notes.trim().isEmpty ? null : notes.trim();

  Future<void> updateEntry(
    Entry original,
    EntryDraft draft,
  ) => db.transaction(() async {
    final existing = await (db.select(
      db.entries,
    )..where((e) => e.id.equals(original.id))).getSingleOrNull();
    if (existing == null ||
        existing.exerciseId != draft.exerciseId ||
        DateTime.parse(existing.updatedAt) != original.updatedAt) {
      throw const TrackerException(
        'This entry changed. Reopen it before editing.',
      );
    }
    final exercise = await _findExercise(existing.exerciseId);
    _validateDraft(draft, Measurement.values.byName(exercise.measurement));
    final owned = original.sets.map((s) => s.id).toSet();
    final supplied = draft.sets.map((s) => s.id).nonNulls.toList();
    if (!owned.containsAll(supplied) ||
        supplied.toSet().length != supplied.length) {
      throw const TrackerException('A set no longer belongs to this entry.');
    }
    await (db.update(db.entries)..where((e) => e.id.equals(original.id))).write(
      EntriesCompanion(
        activityDate: Value(draft.day.iso),
        notes: Value(_cleanNotes(draft.notes)),
        updatedAt: Value(_timestampAfter(existing.updatedAt)),
      ),
    );
    await (db.delete(
      db.exerciseSets,
    )..where((s) => s.entryId.equals(original.id))).go();
    await db.batch(
      (b) => b.insertAll(db.exerciseSets, [
        for (final (i, set) in draft.sets.indexed)
          ExerciseSetsCompanion.insert(
            id: set.id ?? newId(),
            entryId: original.id,
            position: i,
            value: set.value,
            reps: Value(set.reps),
          ),
      ]),
    );
  });

  Future<void> deleteEntry(String id) => db.transaction(() async {
    await (db.delete(db.entries)..where((e) => e.id.equals(id))).go();
    // The database cascades set deletions; notify Drift's set queries too.
    db.markTablesUpdated([db.exerciseSets]);
  });

  Stream<List<Entry>> watchEntries({
    String? exerciseId,
    CalendarDay? day,
    String search = '',
    int? limit,
    int offset = 0,
  }) => _entriesQuery(
    exerciseId: exerciseId,
    day: day,
    search: search,
    limit: limit,
    offset: offset,
    includeArchived: false,
  ).watch().map(_readEntries);

  Selectable<QueryRow> _entriesQuery({
    String? exerciseId,
    CalendarDay? day,
    String search = '',
    int? limit,
    int offset = 0,
    bool includeArchived = true,
  }) {
    final joinsExercise = search.isNotEmpty || !includeArchived;
    final conditions = [
      if (exerciseId != null) 'e.exercise_id = ?',
      if (day != null) 'e.activity_date = ?',
      if (search.isNotEmpty) 'instr(x.normalized_name, ?) > 0',
      if (!includeArchived) 'x.archived = 0',
    ];
    return db.customSelect(
      """
      WITH wanted AS (
        SELECT e.* FROM entries e
        ${joinsExercise ? 'JOIN exercises x ON x.id = e.exercise_id' : ''}
        ${conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}'}
        ORDER BY e.activity_date DESC, e.entry_order DESC
        LIMIT ? OFFSET ?
      )
      SELECT e.*, s.id AS set_id, s.position, s.value, s.reps
      FROM wanted e JOIN exercise_sets s ON s.entry_id=e.id
      ORDER BY e.activity_date DESC, e.entry_order DESC, s.position ASC
      """,
      variables: [
        if (exerciseId != null) Variable(exerciseId),
        if (day != null) Variable(day.iso),
        if (search.isNotEmpty) Variable(search),
        Variable(limit ?? -1),
        Variable(offset),
      ],
      readsFrom: {db.entries, db.exerciseSets, if (joinsExercise) db.exercises},
    );
  }

  List<Entry> _readEntries(List<QueryRow> rows) {
    final grouped = <String, (QueryRow, List<RecordedSet>)>{};
    for (final row in rows) {
      final id = row.read<String>('id');
      final item = grouped.putIfAbsent(id, () => (row, []));
      item.$2.add((
        id: row.read<String>('set_id'),
        position: row.read<int>('position'),
        value: row.read<int>('value'),
        reps: row.readNullable<int>('reps'),
      ));
    }
    return List.unmodifiable(
      grouped.values.map((item) {
        final (r, sets) = item;
        return Entry(
          id: r.read<String>('id'),
          exerciseId: r.read<String>('exercise_id'),
          day: CalendarDay.parse(r.read<String>('activity_date')),
          notes: r.readNullable<String>('notes'),
          order: r.read<int>('entry_order'),
          createdAt: DateTime.parse(r.read<String>('created_at')),
          updatedAt: DateTime.parse(r.read<String>('updated_at')),
          sets: sets,
        );
      }),
    );
  }

  Stream<Set<CalendarDay>> watchRecordedDays({
    required CalendarDay start,
    required CalendarDay end,
    String? exerciseId,
  }) => db
      .customSelect(
        '''
    SELECT DISTINCT activity_date FROM entries e
    JOIN exercises x ON x.id=e.exercise_id
    WHERE activity_date BETWEEN ?1 AND ?2
      AND (?3 IS NULL OR e.exercise_id = ?3) AND x.archived = 0
    ''',
        variables: [
          Variable(start.iso),
          Variable(end.iso),
          Variable<String>(exerciseId),
        ],
        readsFrom: {db.entries, db.exercises},
      )
      .watch()
      .map(
        (rows) => Set.unmodifiable(
          rows.map((r) => CalendarDay.parse(r.read<String>('activity_date'))),
        ),
      );

  static const _daysSql = '''
    WITH ranked AS (
      SELECT e.exercise_id, e.activity_date, s.value, s.reps,
        ROW_NUMBER() OVER (
          PARTITION BY e.exercise_id, e.activity_date ORDER BY e.entry_order, s.position
        ) AS asc_rank,
        ROW_NUMBER() OVER (
          PARTITION BY e.exercise_id, e.activity_date ORDER BY e.entry_order DESC, s.position DESC
        ) AS desc_rank
      FROM entries e JOIN exercise_sets s ON s.entry_id=e.id
      WHERE
    ''';
  static const _dailyColumns = '''
    SELECT exercise_id, activity_date,
      MAX(CASE WHEN asc_rank=1 THEN value END) AS first_set,
      MAX(CASE WHEN desc_rank=1 THEN value END) AS latest_set,
      MAX(CASE WHEN reps = 0 THEN 0 ELSE value END) AS best_set,
      SUM(value) AS volume, COUNT(*) AS set_count
    FROM ranked GROUP BY exercise_id, activity_date
    ''';

  DailyResult _day(QueryRow r) => (
    day: CalendarDay.parse(r.read<String>('activity_date')),
    first: r.read<int>('first_set'),
    latest: r.read<int>('latest_set'),
    best: r.read<int>('best_set'),
    total: r.read<int>('volume'),
    count: r.read<int>('set_count'),
  );

  Stream<Performance> watchPerformance(String id, DayRange range) => db
      .customSelect(
        '''
    $_daysSql e.exercise_id = ?1
      AND e.activity_date BETWEEN ?2 AND ?3
    )
    $_dailyColumns ORDER BY activity_date
    ''',
        variables: [
          Variable(id),
          Variable(range.start?.iso ?? '1900-01-01'),
          Variable(range.end?.iso ?? '9999-12-31'),
        ],
        readsFrom: {db.entries, db.exerciseSets},
      )
      .watch()
      .map((rows) => Performance(rows.map(_day)));

  Future<OverviewData> _overview() => db.transaction(() async {
    final rows = await db
        .customSelect(
          '''
      $_daysSql EXISTS (SELECT 1 FROM exercises x WHERE x.id=e.exercise_id AND x.archived=0)),
      daily AS ($_dailyColumns),
      summaries AS (
        SELECT daily.*,
          first_value(first_set) OVER whole_exercise AS lifetime_first,
          min(activity_date) OVER whole_exercise AS lifetime_first_day,
          max(best_set) OVER whole_exercise AS lifetime_best,
          sum(set_count) OVER whole_exercise AS lifetime_count,
          row_number() OVER recent_days AS recent_rank
        FROM daily
        WINDOW
          whole_exercise AS (
            PARTITION BY exercise_id ORDER BY activity_date
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
          ),
          recent_days AS (PARTITION BY exercise_id ORDER BY activity_date DESC)
      )
      SELECT * FROM summaries WHERE recent_rank <= 16
      ORDER BY exercise_id, activity_date
      ''',
          readsFrom: {db.entries, db.exerciseSets, db.exercises},
        )
        .get();
    final groups = <String, List<QueryRow>>{};
    for (final r in rows) {
      groups.putIfAbsent(r.read<String>('exercise_id'), () => []).add(r);
    }
    final summaries = <OverviewExercise>[];
    CalendarDay? first;
    for (final group in groups.entries) {
      final r = group.value.last;
      final lastDay = CalendarDay.parse(r.read<String>('activity_date'));
      final firstDay = CalendarDay.parse(r.read<String>('lifetime_first_day'));
      if (first == null || firstDay.isBefore(first)) first = firstDay;
      summaries.add((
        exerciseId: group.key,
        first: r.read<int>('lifetime_first'),
        latest: r.read<int>('latest_set'),
        best: r.read<int>('lifetime_best'),
        count: r.read<int>('lifetime_count'),
        firstDay: firstDay,
        latestDay: lastDay,
        trend: List.unmodifiable(group.value.map(_day)),
      ));
    }
    summaries.sort((a, b) {
      final byDate = b.latestDay.compareTo(a.latestDay);
      return byDate != 0 ? byDate : a.exerciseId.compareTo(b.exerciseId);
    });
    return (
      exercises: List<OverviewExercise>.unmodifiable(summaries),
      firstDay: first,
      recent: _readEntries(
        await _entriesQuery(limit: 3, includeArchived: false).get(),
      ),
    );
  });

  Stream<OverviewData> watchOverview() => db
      .tableUpdates(
        TableUpdateQuery.onAllTables([
          db.entries,
          db.exerciseSets,
          db.exercises,
        ]),
      )
      .startWithInitial(_overview);

  Stream<Goal?> watchGoal(String exerciseId) =>
      (db.select(db.goals)..where((g) => g.exerciseId.equals(exerciseId)))
          .watchSingleOrNull()
          .map((r) => r == null ? null : _goal(r));

  Future<void> saveGoal(String id, int target, CalendarDay? deadline) async {
    if (setValueError(target) case final error?) throw TrackerException(error);
    await db
        .into(db.goals)
        .insertOnConflictUpdate(
          GoalsCompanion.insert(
            exerciseId: id,
            target: target,
            deadline: Value(deadline?.iso),
            updatedAt: _timestamp,
          ),
        );
  }

  Future<void> removeGoal(String id) =>
      (db.delete(db.goals)..where((g) => g.exerciseId.equals(id))).go();

  Future<BackupData> snapshot() => db.transaction(_snapshot);

  Future<BackupData> _snapshot() async => BackupData(
    exercises: (await (db.select(
      db.exercises,
    )..orderBy([(e) => OrderingTerm.asc(e.id)])).get()).map(_exercise),
    entries: _readEntries(await _entriesQuery().get()),
    goals: (await (db.select(
      db.goals,
    )..orderBy([(g) => OrderingTerm.asc(g.exerciseId)])).get()).map(_goal),
    preferences: _preferences(
      await db.select(db.appPreferences).getSingleOrNull(),
    ),
    body: await _bodySnapshot(),
    receipts: {
      for (final r in await db.select(db.importReceipts).get())
        r.fingerprint: DateTime.parse(r.importedAt),
    },
  );

  /// The transfer layer computes a complete write plan from the current snapshot.
  /// For replacement, [recover] must finish successfully before any deletion.
  Future<void> restore(
    BackupWrite Function(BackupData current) plan, {
    Future<void> Function(BackupData current)? recover,
  }) => db.transaction(() async {
    final current = await _snapshot();
    final write = plan(current);
    if (write.replace) {
      if (recover == null) {
        throw StateError('Replacement requires a recovery backup.');
      }
      await recover(current);
      await _clearExercises();
      if (write.data.body != null) await db.delete(db.weighIns).go();
    }
    await db.batch((b) {
      b.insertAll(
        db.exercises,
        write.data.exercises.map(
          (x) => ExercisesCompanion.insert(
            id: x.id,
            name: x.name,
            normalizedName: normalizeName(x.name),
            measurement: x.measurement.name,
            trackSets: Value(x.trackSets),
            archived: Value(x.archived),
            createdAt: x.createdAt.toIso8601String(),
            updatedAt: x.updatedAt.toIso8601String(),
          ),
        ),
      );
      b.insertAll(
        db.entries,
        write.data.entries.map(
          (e) => EntriesCompanion.insert(
            id: e.id,
            exerciseId: e.exerciseId,
            activityDate: e.day.iso,
            notes: Value(e.notes),
            entryOrder: e.order,
            createdAt: e.createdAt.toIso8601String(),
            updatedAt: e.updatedAt.toIso8601String(),
          ),
        ),
      );
      b.insertAll(db.exerciseSets, [
        for (final e in write.data.entries)
          for (final s in e.sets)
            ExerciseSetsCompanion.insert(
              id: s.id,
              entryId: e.id,
              position: s.position,
              value: s.value,
              reps: Value(s.reps),
            ),
      ]);
      b.insertAll(
        db.goals,
        write.data.goals.map(
          (g) => GoalsCompanion.insert(
            exerciseId: g.exerciseId,
            target: g.target,
            deadline: Value(g.deadline?.iso),
            updatedAt: g.updatedAt.toIso8601String(),
          ),
        ),
      );
      b.insertAll(
        db.importReceipts,
        write.data.receipts.entries.map(
          (r) => ImportReceiptsCompanion.insert(
            fingerprint: r.key,
            importedAt: r.value.toIso8601String(),
          ),
        ),
      );
      if (write.data.body case final body?) {
        b.insertAll(db.weighIns, [
          for (final record in body.weighIns)
            WeighInsCompanion.insert(day: record.day.iso, grams: record.grams),
        ]);
      }
    });
    if (write.replace) await savePreferences(write.data.preferences);
    if (write.data.body case final body?) {
      await saveProfileDetails(body.profile);
    }
  });

  Future<void> importActivity(
    ActivityWrite Function(BackupData current) plan, {
    bool allowRepeat = false,
  }) => db.transaction(() async {
    final current = await _snapshot();
    final write = plan(current);
    if (current.receipts.containsKey(write.fingerprint) && !allowRepeat) {
      throw const TrackerException(
        'This batch is already imported. Choose Import again to repeat it.',
      );
    }
    final created = <String, String>{};
    final measurements = {
      for (final e in current.exercises) e.id: e.measurement,
    };
    final multipleSets = {
      for (final e in write.entries)
        if (e.sets.length > 1) e.exerciseId,
    };
    for (final spec in write.create) {
      final exercise = await _createExercise(
        spec.name,
        spec.measurement,
        trackSets: multipleSets.contains(spec.key),
      );
      created[spec.key] = exercise.id;
      measurements[exercise.id] = exercise.measurement;
    }
    await _insertDrafts([
      for (final draft in write.entries)
        EntryDraft(
          exerciseId: created[draft.exerciseId] ?? draft.exerciseId,
          day: draft.day,
          notes: draft.notes,
          sets: draft.sets,
        ),
    ], measurements);
    await db
        .into(db.importReceipts)
        .insert(
          ImportReceiptsCompanion.insert(
            fingerprint: write.fingerprint,
            importedAt: _timestamp,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  });
}

extension<T> on Stream<T> {
  Stream<R> startWithInitial<R>(Future<R> Function() read) {
    // Subscribe before the first read so a write during that read is not lost.
    late StreamSubscription<T> subscription;
    var active = true, reading = false, pending = false;
    late StreamController<R> out;
    Future<void> refresh() async {
      if (reading) {
        pending = true;
        return;
      }
      reading = true;
      do {
        pending = false;
        try {
          final value = await read();
          if (active) out.add(value);
        } catch (error, stack) {
          if (active) out.addError(error, stack);
        }
      } while (active && pending);
      reading = false;
    }

    out = StreamController<R>(
      onListen: () {
        subscription = listen((_) => refresh(), onError: out.addError);
        refresh();
      },
      onCancel: () {
        active = false;
        return subscription.cancel();
      },
    );
    return out.stream;
  }
}
