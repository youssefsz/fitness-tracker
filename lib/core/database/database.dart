// Drift reads column checks at generation time.
// ignore_for_file: recursive_getters

import 'package:drift/drift.dart';

import '../../shared/domain/body_metrics.dart';

part 'database.g.dart';

@DataClassName('ExerciseRow')
class Exercises extends Table {
  TextColumn get id => text().withLength(min: 1, max: 80)();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  TextColumn get normalizedName => text().unique()();
  TextColumn get measurement => text().check(
    measurement.isIn(['repetitions', 'duration', 'weight', 'weightAndReps']),
  )();
  BoolColumn get trackSets => boolean().withDefault(const Constant(true))();
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
  IntColumn get value => integer().check(value.isBetweenValues(0, 999999))();
  IntColumn get reps =>
      integer().check(reps.isBetweenValues(0, 999999)).nullable()();

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
  TextColumn get progressExerciseId => text().nullable().references(
    Exercises,
    #id,
    onDelete: KeyAction.setNull,
  )();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ImportReceipts extends Table {
  TextColumn get fingerprint => text().withLength(min: 64, max: 64)();
  TextColumn get importedAt => text()();

  @override
  Set<Column<Object>> get primaryKey => {fingerprint};
}

@DataClassName('ProfileRow')
class LocalProfiles extends Table {
  IntColumn get id => integer().check(id.equals(1))();
  TextColumn get displayName =>
      text().withLength(min: 1, max: maxDisplayName).nullable()();
  IntColumn get heightMillimeters => integer()
      .check(heightMillimeters.isBetweenValues(1, maxHeightMillimeters))
      .nullable()();
  TextColumn get weightUnit => text()
      .check(weightUnit.isIn(['kg', 'lb']))
      .withDefault(const Constant('kg'))();
  BlobColumn get photo => blob().nullable()();
  TextColumn get avatarPreset => text()
      .check(
        avatarPreset.isIn(['anonymous', 'running', 'strength', 'mobility']),
      )
      .withDefault(const Constant('anonymous'))();
  TextColumn get heightUnit => text()
      .check(heightUnit.isIn(['cm', 'ftIn']))
      .withDefault(const Constant('cm'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('WeighInRow')
class WeighIns extends Table {
  TextColumn get day => text().check(
    day.like('____-__-__') &
        day.isBiggerOrEqualValue('1900-01-01') &
        day.isSmallerOrEqualValue('9999-12-31'),
  )();
  IntColumn get grams =>
      integer().check(grams.isBetweenValues(1, maxWeightGrams))();

  @override
  Set<Column<Object>> get primaryKey => {day};
}

@DriftDatabase(
  tables: [
    Exercises,
    Entries,
    ExerciseSets,
    Goals,
    AppPreferences,
    ImportReceipts,
    LocalProfiles,
    WeighIns,
  ],
)
class TrackerDatabase extends _$TrackerDatabase {
  TrackerDatabase(super.executor);

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => transaction(() => m.createAll()),
    onUpgrade: (m, from, to) async {
      if (from < 1 || from > 5 || to != 6) {
        throw StateError(
          'Unsupported database schema transition: $from → $to.',
        );
      }
      if (from == 5) {
        await m.addColumn(appPreferences, appPreferences.progressExerciseId);
        return;
      }
      // Rebuilding exercises must not cascade into existing goals or entries.
      await customStatement('PRAGMA foreign_keys = OFF');
      await transaction(() async {
        if (from == 1) {
          await m.createTable(localProfiles);
          await m.createTable(weighIns);
        } else if (from < 4) {
          if (from == 2) {
            await m.addColumn(localProfiles, localProfiles.avatarPreset);
          }
          await m.addColumn(localProfiles, localProfiles.heightUnit);
        }
        await m.alterTable(
          TableMigration(exercises, newColumns: [exercises.trackSets]),
        );
        await m.alterTable(
          TableMigration(exerciseSets, newColumns: [exerciseSets.reps]),
        );
        await m.addColumn(appPreferences, appPreferences.progressExerciseId);
        if ((await customSelect('PRAGMA foreign_key_check').get()).isNotEmpty) {
          throw StateError('Database migration left invalid references.');
        }
      });
    },
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
  );
}
