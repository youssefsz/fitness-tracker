// Drift reads column checks at generation time.
// ignore_for_file: recursive_getters

import 'package:drift/drift.dart';

part 'database.g.dart';

@DataClassName('ExerciseRow')
class Exercises extends Table {
  TextColumn get id => text().withLength(min: 1, max: 80)();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  TextColumn get normalizedName => text().unique()();
  TextColumn get measurement =>
      text().check(measurement.isIn(['repetitions', 'duration']))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(name: 'entries_by_day', columns: {#activityDate, #entryOrder})
@TableIndex(
  name: 'entries_by_exercise_day',
  columns: {#exerciseId, #activityDate, #entryOrder},
)
class Entries extends Table {
  TextColumn get id => text().withLength(min: 1, max: 80)();
  TextColumn get exerciseId => text().references(Exercises, #id)();
  TextColumn get activityDate => text().check(
    activityDate.like('____-__-__') &
        activityDate.isBiggerOrEqualValue('1900-01-01') &
        activityDate.isSmallerOrEqualValue('9999-12-31'),
  )();
  TextColumn get notes => text().withLength(min: 0, max: 2000).nullable()();
  IntColumn get entryOrder =>
      integer().unique().check(entryOrder.isBiggerThanValue(0))();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ExerciseSets extends Table {
  TextColumn get id => text().withLength(min: 1, max: 80)();
  TextColumn get entryId =>
      text().references(Entries, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer().check(position.isBetweenValues(0, 99))();
  IntColumn get value => integer().check(value.isBetweenValues(1, 999999))();

  @override
  Set<Column<Object>> get primaryKey => {id};
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {entryId, position},
  ];
}

@DataClassName('GoalRow')
class Goals extends Table {
  TextColumn get exerciseId =>
      text().references(Exercises, #id, onDelete: KeyAction.cascade)();
  IntColumn get target => integer().check(target.isBetweenValues(1, 999999))();
  TextColumn get deadline => text().nullable()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column<Object>> get primaryKey => {exerciseId};
}

class AppPreferences extends Table {
  IntColumn get id => integer().check(id.equals(1))();
  TextColumn get appearance =>
      text().check(appearance.isIn(['system', 'light', 'dark']))();
  TextColumn get durationStyle =>
      text().check(durationStyle.isIn(['clock', 'seconds']))();
  BoolColumn get haptics => boolean()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ImportReceipts extends Table {
  TextColumn get fingerprint => text().withLength(min: 64, max: 64)();
  TextColumn get importedAt => text()();

  @override
  Set<Column<Object>> get primaryKey => {fingerprint};
}

@DriftDatabase(
  tables: [
    Exercises,
    Entries,
    ExerciseSets,
    Goals,
    AppPreferences,
    ImportReceipts,
  ],
)
class TrackerDatabase extends _$TrackerDatabase {
  TrackerDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => transaction(() => m.createAll()),
    onUpgrade: (m, from, to) async {
      throw StateError('Unsupported database schema transition: $from → $to.');
    },
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
  );
}
