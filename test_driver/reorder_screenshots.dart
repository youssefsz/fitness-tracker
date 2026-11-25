import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  writeResponseOnFailure: true,
  onScreenshot:
      (String name, List<int> bytes, [Map<String, Object?>? args]) async {
        final output = Directory(
          Platform.environment['FITNESS_REORDER_SCREENSHOTS'] ??
              'build/qa/exercise-order',
        );
        await output.create(recursive: true);
        await File('${output.path}/$name.png').writeAsBytes(bytes);
        return true;
      },
  responseDataCallback: (_) async {},
);
