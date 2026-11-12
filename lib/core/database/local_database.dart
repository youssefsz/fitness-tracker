import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'database.dart';

TrackerDatabase openLocalDatabase() => TrackerDatabase(
  LazyDatabase(() async {
    final directory = await getApplicationSupportDirectory();
    final temporary = await getTemporaryDirectory();
    return NativeDatabase.createInBackground(
      File(p.join(directory.path, 'fitness.sqlite')),
      isolateSetup: () => sqlite3.tempDirectory = temporary.path,
    );
  }),
);
