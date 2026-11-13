import 'dart:io';

import 'package:drift/native.dart';
import 'package:fitness_tracker/app/providers.dart';
import 'package:fitness_tracker/core/database/database.dart'
    show TrackerDatabase;
import 'package:fitness_tracker/core/database/tracker_repository.dart';
import 'package:fitness_tracker/core/platform/device_services.dart';
import 'package:fitness_tracker/features/data_transfer/transfer_codec.dart';
import 'package:fitness_tracker/features/profile/profile_page.dart';
import 'package:fitness_tracker/main.dart';
import 'package:fitness_tracker/shared/domain/body_metrics.dart';
import 'package:fitness_tracker/shared/domain/training.dart';
import 'package:fitness_tracker/shared/widgets/ui.dart' show LargeNumberField;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final _now = DateTime(2026, 11, 12, 12);
final _today = CalendarDay.fromDate(_now);

Finder _visible(String label) => find.text(label).hitTestable();

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 25),
  );
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsWidgets);
}

Future<void> _reveal(WidgetTester tester, Finder widget) async {
  if (widget.hitTestable().evaluate().isNotEmpty) return;
  final scroll = find.byType(CustomScrollView).hitTestable();
  if (widget.evaluate().isEmpty && scroll.evaluate().isNotEmpty) {
    final scrollable = find
        .descendant(of: scroll.first, matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(
      widget,
      170,
      scrollable: scrollable,
      maxScrolls: 12,
    );
    await _settle(tester);
  }
  if (widget.hitTestable().evaluate().isEmpty && widget.evaluate().isNotEmpty) {
    await Scrollable.ensureVisible(tester.element(widget.last), alignment: .45);
    await _settle(tester);
  }
}

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.pump();
  final widget = find.text(text, skipOffstage: false);
  await _reveal(tester, widget);
  expect(
    _visible(text),
    findsWidgets,
    reason: 'Expected a visible "$text" control.',
  );
  await tester.tap(_visible(text).first);
  await _settle(tester);
}

Future<void> _tooltip(WidgetTester tester, String label) async {
  final widget = find.byTooltip(label, skipOffstage: false);
  await _reveal(tester, widget);
  expect(
    widget.hitTestable(),
    findsWidgets,
    reason: 'Expected a visible "$label" control.',
  );
  await tester.tap(widget.hitTestable().first);
  await _settle(tester);
}

Future<void> _present(
  WidgetTester tester,
  TrackerRepository repo, {
  ProfilePhotos? photos,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        nowProvider.overrideWithValue(() => _now),
        if (photos != null) profilePhotosProvider.overrideWithValue(photos),
      ],
      child: const FitnessApp(),
    ),
  );
  await _settle(tester);
  await _waitFor(tester, _visible('Overview'));
}

class _FixturePhotos implements ProfilePhotos {
  @override
  Future<Uint8List?> recover() async => null;

  @override
  Future<Uint8List> pick() async {
    final data = await rootBundle.load('assets/brand/mark.png');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> capture(String name) async {
    // These optional QA captures use the iOS screenshot path. Keep the
    // behavior checks independent of screenshot setup on other targets.
    if (!Platform.isIOS) return;
    final bytes = await binding.takeScreenshot(name);
    const hostPath = String.fromEnvironment('V_QA_PATH');
    final base = await getTemporaryDirectory();
    final directory = Directory(
      hostPath.isEmpty ? p.join(base.path, 'v-integration-captures') : hostPath,
    );
    await directory.create(recursive: true);
    await File(p.join(directory.path, '$name.png')).writeAsBytes(bytes);
  }

  testWidgets(
    'log two exercise types, backdate, compare, edit, goal, archive, reopen and delete',
    (tester) async {
      tester.testTextInput.register();
      addTearDown(tester.testTextInput.unregister);
      final directory = await Directory.systemTemp.createTemp('v-integration-');
      final database = File(p.join(directory.path, 'fitness.sqlite'));
      TrackerRepository open() => TrackerRepository(
        TrackerDatabase(NativeDatabase.createInBackground(database)),
        now: () => _now,
      );
      var repo = open();
      try {
        await _present(tester, repo);
        await _waitFor(tester, _visible('Start with one result.'));
        await capture('01-empty');

        await _tap(tester, 'History');
        await _tap(tester, '11');
        await _tap(tester, 'Add');
        await _tap(tester, 'Create exercise');
        await tester.enterText(find.byType(TextField).first, 'Push-ups');
        await _tap(tester, 'Track sets');
        await _tap(tester, 'Create exercise');
        expect(find.text('11 Nov 2026'), findsOneWidget);
        await tester.enterText(find.byType(TextFormField).first, '22');
        await _tap(tester, 'Add set');
        await tester.enterText(find.byType(TextFormField).first, '20');
        await _tap(tester, 'Add set');
        await tester.enterText(find.byType(TextFormField).first, '18');
        await _tap(tester, 'Add another exercise');
        await _tap(tester, 'Create exercise');
        await tester.enterText(find.byType(TextField).first, 'Plank');
        await _tap(tester, 'Duration');
        await _tap(tester, 'Track sets');
        await _tap(tester, 'Create exercise');
        await _reveal(
          tester,
          find.descendant(
            of: find.byWidgetPredicate(
              (w) => w is LargeNumberField && w.label == 'Minutes',
              skipOffstage: false,
            ),
            matching: find.byType(TextFormField),
          ),
        );
        await tester.enterText(
          find.descendant(
            of: find.byWidgetPredicate(
              (w) => w is LargeNumberField && w.label == 'Minutes',
              skipOffstage: false,
            ),
            matching: find.byType(TextFormField),
          ),
          '1',
        );
        await tester.enterText(
          find.descendant(
            of: find.byWidgetPredicate(
              (w) => w is LargeNumberField && w.label == 'Seconds',
              skipOffstage: false,
            ),
            matching: find.byType(TextFormField),
          ),
          '40',
        );
        await _tap(tester, 'Save 4 sets');
        expect(find.text('Latest 18 reps · Best 22 reps'), findsOneWidget);
        expect(find.text('1:40'), findsOneWidget);
        await capture('02-history');

        final recorded = await repo.snapshot();
        expect(recorded.entries, hasLength(2));
        expect(recorded.entries.map((e) => e.day).toSet(), {
          _today.plusDays(-1),
        });
        await _tap(tester, 'Overview');
        expect(find.text('18 reps'), findsWidgets);
        await capture('03-overview');
        await _tap(tester, 'Progress');
        await _tap(tester, 'Plank');
        await _tap(tester, 'Push-ups');
        await _tap(tester, 'Best result');
        expect(find.textContaining('22 reps'), findsWidgets);
        await _tap(tester, 'View values');
        expect(find.text('Best result by date'), findsOneWidget);
        await _tap(tester, '11 Nov 2026');
        await _tap(tester, 'All time');
        await _tap(tester, 'Last 7 days');
        await _tap(tester, 'Apply range');
        expect(find.text('Last 7 days'), findsOneWidget);
        await capture('04-progress');

        await _tap(tester, 'History');
        await _tooltip(tester, 'Options for Push-ups on 11 Nov 2026');
        await _tap(tester, 'Edit entry');
        await _tap(tester, 'Set 1');
        await tester.enterText(find.byType(TextFormField).first, '24');
        await _tap(tester, 'Save changes');
        expect(find.text('Latest 18 reps · Best 24 reps'), findsOneWidget);
        await _tap(tester, 'Overview');
        await _tap(tester, 'Push-ups');
        await _tap(tester, 'Set goal');
        await tester.enterText(find.byType(TextField).first, '24');
        await _tap(tester, 'Save goal');
        expect(find.text('Achieved'), findsOneWidget);
        await _tap(tester, 'Edit goal');
        await tester.enterText(find.byType(TextField).first, '25');
        await _tap(tester, 'Save goal');
        expect(find.text('1 rep to go'), findsOneWidget);
        await _tap(tester, 'Edit goal');
        await _tap(tester, 'Remove goal');
        final remove = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Remove goal'),
        );
        await tester.tap(remove);
        await _settle(tester);
        expect(find.text('Set goal'), findsOneWidget);

        await _tooltip(tester, 'Exercise options');
        await _tap(tester, 'Archive exercise');
        await _tap(tester, 'Archive');
        expect(find.text('Repetitions · Archived'), findsOneWidget);
        await _tap(tester, 'Restore exercise');
        expect(find.text('Repetitions · Archived'), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await _settle(tester);
        await repo.close();
        repo = open();
        await _present(tester, repo);
        await _waitFor(tester, _visible('18 reps'));
        final restored = await repo.snapshot();
        expect(
          restored.entries.where((e) => e.sets.length == 3).single.best,
          24,
        );

        await _tap(tester, 'History');
        await _tap(tester, '11');
        await _tooltip(tester, 'Options for Push-ups on 11 Nov 2026');
        await _tap(tester, 'Delete entry');
        await _tap(tester, 'Delete entry');
        expect(find.textContaining('Best 24 reps'), findsNothing);
        expect((await repo.snapshot()).entries.single.sets.single.value, 100);
        expect(tester.takeException(), isNull);
      } catch (_) {
        await capture('log-failure');
        rethrow;
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _settle(tester);
        await repo.close();
        await directory.delete(recursive: true);
      }
    },
  );

  testWidgets('validate AI paste, reject bad data and block a repeated batch', (
    tester,
  ) async {
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    final repo = TrackerRepository(
      TrackerDatabase(NativeDatabase.memory()),
      now: () => _now,
    );
    try {
      await _present(tester, repo);
      await _tooltip(tester, 'Profile');
      await _tap(tester, 'Your data');
      await _tap(tester, 'Import from AI chat');
      await _tap(tester, 'Copy AI prompt');
      expect(find.text('Prompt copied.'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField).first,
        '{"format":"wrong"}',
      );
      await _tap(tester, 'Validate and preview');
      expect(
        find.textContaining('Expected fitness-activity-import'),
        findsOneWidget,
      );
      expect((await repo.snapshot()).entries, isEmpty);
      await tester.enterText(
        find.byType(TextField).first,
        activityExample(_today),
      );
      await _tap(tester, 'Validate and preview');
      expect(
        find.widgetWithText(FilledButton, 'Confirm import'),
        findsOneWidget,
      );
      await _reveal(tester, find.text('Import preview', skipOffstage: false));
      expect(find.text('Import preview'), findsOneWidget);
      expect(find.textContaining('Create "Plank"'), findsOneWidget);
      await _tap(tester, 'Confirm import');
      expect((await repo.snapshot()).entries, hasLength(4));

      await _tap(tester, 'Import from AI chat');
      await tester.enterText(
        find.byType(TextField).first,
        activityExample(_today),
      );
      await _tap(tester, 'Validate and preview');
      await _reveal(tester, find.text('Import again', skipOffstage: false));
      expect(find.text('Import again'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Confirm import'),
      );
      expect(button.onPressed, isNull);
      await capture('05-ai-preview');
      await _tap(tester, 'Import again');
      await _tap(tester, 'Confirm import');
      final data = await repo.snapshot();
      expect(data.entries, hasLength(8));
      expect(data.receipts, hasLength(1));
      expect(tester.takeException(), isNull);
    } catch (_) {
      await capture('transfer-failure');
      rethrow;
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
      await repo.close();
    }
  });

  testWidgets(
    'profile edits, dated weights, preferences and installed version',
    (tester) async {
      tester.testTextInput.register();
      addTearDown(tester.testTextInput.unregister);
      final repo = TrackerRepository(
        TrackerDatabase(NativeDatabase.memory()),
        now: () => _now,
      );
      try {
        await _present(tester, repo, photos: _FixturePhotos());
        await _tooltip(tester, 'Profile');
        expect(_visible('You'), findsOneWidget);
        await _tap(tester, 'Edit profile');
        final avatar = find.byType(ProfileAvatar);
        final changeAvatar = _visible('Change avatar');
        expect(
          tester.getCenter(avatar).dx,
          closeTo(tester.getCenter(changeAvatar).dx, 1),
        );
        expect(
          tester.getBottomLeft(avatar).dy,
          lessThan(tester.getTopLeft(changeAvatar).dy),
        );
        await capture('06-edit-profile');
        await _tap(tester, 'Change avatar');
        await _tap(tester, 'Strength');
        expect(
          (await repo.watchProfile().first).avatarPreset,
          AvatarPreset.strength,
        );
        await _tap(tester, 'Change avatar');
        await _tap(tester, 'Choose from gallery');
        expect((await repo.watchProfile().first).photo, isNotEmpty);
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Display name'),
          'Sam',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Height'),
          '178.5',
        );
        await _tap(tester, 'Save profile');
        expect(_visible('Sam'), findsOneWidget);
        expect(_visible('178.5 cm'), findsOneWidget);
        expect((await repo.watchProfile().first).photo, isNotEmpty);

        await _tap(tester, 'Edit profile');
        await _tap(tester, 'Height unit');
        await _tap(tester, 'Feet and inches');
        await capture('06-edit-profile-feet-inches');
        await _tap(tester, 'Save profile');
        expect(_visible('5 ft 10.28 in'), findsOneWidget);
        final imperial = (await repo.watchProfile().first).details;
        expect(imperial.heightMillimeters, 1785);
        expect(imperial.heightUnit, HeightUnit.ftIn);
        expect(imperial.weightUnit, WeightUnit.kg);

        await _tap(tester, 'Log weight');
        final weightField = find.byType(TextFormField);
        await tester.enterText(weightField, '80.125');
        await _tap(tester, 'lb');
        expect(
          tester.widget<TextFormField>(weightField).controller!.text,
          '176.65',
        );
        await capture('07-log-weight');
        await _tap(tester, 'kg');
        expect(
          tester.widget<TextFormField>(weightField).controller!.text,
          '80.125',
        );
        await _tap(tester, 'Save weight');
        expect(_visible('80.125 kg'), findsOneWidget);
        await _tap(tester, 'Log weight');
        await tester.enterText(find.byType(TextFormField), '81.5');
        await _tap(tester, 'Date');
        await _tap(tester, '10');
        await _tap(tester, 'OK');
        await _tap(tester, 'Save weight');
        expect(_visible('80.125 kg'), findsOneWidget);
        await capture('06-profile');

        await _tap(tester, 'Body weight');
        expect(_visible('Weight history'), findsOneWidget);
        expect(find.text('Recent trend'), findsOneWidget);
        expect(find.text('81.5 kg'), findsOneWidget);
        await capture('07-weight-history');
        await _tap(tester, '10 Nov 2026');
        await tester.enterText(find.byType(TextFormField), '81.25');
        await _tap(tester, 'Save weight');
        expect(find.text('81.25 kg'), findsOneWidget);
        await _tap(tester, '10 Nov 2026');
        await _tap(tester, 'Delete weigh-in');
        await _tap(tester, 'Delete weigh-in');
        expect((await repo.snapshot()).body!.weighIns.single.grams, 80125);
        await _tap(tester, '12 Nov 2026');
        await _tap(tester, 'lb');
        await _tap(tester, 'Save weight');
        final body = (await repo.snapshot()).body!;
        expect(body.weighIns.single.grams, 80125);
        expect(body.profile.weightUnit, WeightUnit.lb);
        expect(body.profile.heightUnit, HeightUnit.ftIn);
        await _tooltip(tester, 'Back');
        expect(_visible('176.65 lb'), findsOneWidget);

        await _tap(tester, 'Appearance');
        await capture('08-appearance-picker');
        await _tap(tester, 'Dark');
        expect((await repo.snapshot()).preferences.appearance, Appearance.dark);
        await _tap(tester, 'Duration display');
        await _tap(tester, 'Seconds');
        expect(_visible('90 sec'), findsOneWidget);
        await capture('08-profile-dark');
        final info = await installedAppBuild();
        final version = 'Version ${info.version} (${info.number})';
        await _reveal(tester, find.text(version));
        expect(_visible(version), findsOneWidget);
        expect(find.text('Licenses'), findsOneWidget);
        await capture('09-profile-footer');
        await tester.drag(
          find.byType(CustomScrollView).hitTestable().first,
          const Offset(0, 640),
        );
        await _settle(tester);
        await _tap(tester, 'Edit profile');
        await _tap(tester, 'Change avatar');
        await _tap(tester, 'Remove photo');
        final restoredAvatar = await repo.watchProfile().first;
        expect(restoredAvatar.photo, isNull);
        expect(restoredAvatar.avatarPreset, AvatarPreset.strength);
        expect(tester.takeException(), isNull);
      } catch (_) {
        await capture('profile-failure');
        rethrow;
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _settle(tester);
        await repo.close();
      }
    },
  );
}
