import 'package:drift/native.dart';
import 'package:fitness_tracker/app/providers.dart';
import 'package:fitness_tracker/core/database/database.dart'
    show TrackerDatabase;
import 'package:fitness_tracker/core/database/tracker_repository.dart';
import 'package:fitness_tracker/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

final _now = DateTime(2026, 11, 26, 12);

Finder _switchFor(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(SwitchListTile));

Future<void> _openProfile(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Profile'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('rest timer preference defaults off and persists both changes', (
    tester,
  ) async {
    final repository = TrackerRepository(
      TrackerDatabase(NativeDatabase.memory()),
      now: () => _now,
    );
    try {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(402, 874);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repository),
            nowProvider.overrideWithValue(() => _now),
          ],
          child: const FitnessApp(),
        ),
      );
      await tester.pumpAndSettle();
      await _openProfile(tester);

      var toggle = _switchFor('Rest timer');
      await tester.ensureVisible(toggle);
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await _openProfile(tester);
      toggle = _switchFor('Rest timer');
      await tester.ensureVisible(toggle);
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await repository.close();
    }
  });
}
