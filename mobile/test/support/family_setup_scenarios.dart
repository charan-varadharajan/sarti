import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_controller.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_screen.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/child_profile_editor.dart';
import 'package:sodium/sodium.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import 'child_sync_fixture.dart';
import 'sarti_test_harness.dart';

void familySetupScenarios() {
  late Sodium sodium;
  setUpAll(() async {
    tz_data.initializeTimeZones();
    sodium = await SodiumInit.init();
  });

  Future<SartiTestHarness> blank(WidgetTester tester) async {
    final h = SartiTestHarness.create(fixture: SartiTestFixture.blankDevice);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      h.controller.dispose();
      h.close();
    });
    await h.pumpCalendar(tester);
    await tester.tap(find.text('Create family'));
    await tester.pumpAndSettle();
    return h;
  }

  Future<void> openChild(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('setup-add-child')));
    await tester.tap(find.byKey(const Key('setup-add-child')));
    await tester.pumpAndSettle();
  }

  Future<void> addChild(
    WidgetTester tester,
    String name, {
    String? colour,
  }) async {
    await openChild(tester);
    await tester.enterText(find.byKey(const Key('child-name')), name);
    if (colour != null) {
      await tester.ensureVisible(find.byKey(Key('child-colour-$colour')));
      await tester.tap(find.byKey(Key('child-colour-$colour')));
    }
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('child-save')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'FAMILY-MOB-001 names are drafts until Continue; back writes nothing',
    (tester) async {
      final h = await blank(tester);
      await tester.enterText(
        find.byKey(const Key('setup-family-name')),
        'Prepared family',
      );
      await tester.enterText(find.byKey(const Key('setup-owner-name')), 'Alex');
      expect(h.repository.load(), isNull);
      expect(h.database.raw.select('SELECT 1 FROM outbox'), isEmpty);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Create family'), findsOneWidget);
      expect(h.repository.load(), isNull);
    },
  );

  testWidgets(
    'FAMILY-MOB-002 named family, two coloured children and open calendar',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final h = await blank(tester);
      await tester.enterText(
        find.byKey(const Key('setup-family-name')),
        '  Prepared family  ',
      );
      await tester.enterText(
        find.byKey(const Key('setup-owner-name')),
        '  Alex  ',
      );
      await tester.ensureVisible(find.byKey(const Key('setup-continue')));
      await tester.tap(find.byKey(const Key('setup-continue')));
      await tester.pumpAndSettle();
      expect(h.controller.family!.name, 'Prepared family');
      expect(h.controller.family!.guardians.single.name, 'Alex');
      expect(h.controller.family!.children, isEmpty);
      await addChild(tester, 'Mia', colour: 'rose');
      await addChild(tester, 'Jithu');
      final children = h.repository.load()!.children;
      expect(children.map((c) => c.name), ['Jithu', 'Mia']);
      expect(children.map((c) => c.colorArgb).toSet(), hasLength(2));
      expect(
        children.singleWhere((c) => c.name == 'Mia').colorArgb,
        0xfff3bfd1,
      );
      expect(
        h.database.raw
            .select('SELECT share_with_calendar_guardians FROM child_sync')
            .every((row) => row['share_with_calendar_guardians'] == 0),
        isTrue,
      );
      expect(
        h.database.raw.select(
          "SELECT 1 FROM outbox WHERE kind='family_created'",
        ),
        hasLength(1),
      );
      expect(
        h.database.raw.select(
          "SELECT 1 FROM outbox WHERE kind='child_created'",
        ),
        hasLength(2),
      );
      await tester.ensureVisible(find.byKey(const Key('setup-open-calendar')));
      await tester.tap(find.byKey(const Key('setup-open-calendar')));
      await tester.pumpAndSettle();
      expect(find.text('Prepared family'), findsOneWidget);
      expect(
        find.widgetWithText(FloatingActionButton, 'Event'),
        findsOneWidget,
      );
      expect(h.repository.load()!.events, isEmpty);
    },
  );

  testWidgets(
    'FAMILY-MOB-003 child setup is optional and back preserves explicit saves',
    (tester) async {
      final h = await blank(tester);
      await tester.tap(find.byKey(const Key('setup-continue')));
      await tester.pumpAndSettle();
      expect(h.repository.load()!.name, 'My family');
      await addChild(tester, 'Sam');
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Today'), findsOneWidget);
      expect(h.repository.load()!.children.single.name, 'Sam');
      expect(h.database.raw.select('SELECT 1 FROM households'), hasLength(1));
    },
  );

  testWidgets(
    'FAMILY-MOB-004 invalid private alias retains draft and writes no child',
    (tester) async {
      final h = await blank(tester);
      await tester.tap(find.byKey(const Key('setup-continue')));
      await tester.pumpAndSettle();
      await openChild(tester);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('child-save')))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byKey(const Key('child-name')), 'Mia');
      await tester.ensureVisible(find.byKey(const Key('child-alias')));
      await tester.enterText(find.byKey(const Key('child-alias')), 'mia');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('child-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('child-error')), findsOneWidget);
      expect(h.repository.load()!.children, isEmpty);
      expect(
        h.database.raw.select(
          "SELECT 1 FROM outbox WHERE kind='child_created'",
        ),
        isEmpty,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('setup-open-calendar')));
      await tester.pumpAndSettle();
      expect(find.text('Today'), findsOneWidget);
    },
  );

  testWidgets(
    'FAMILY-SEC-001 revocation while child form is open blocks a write',
    (tester) async {
      final h = await blank(tester);
      await tester.tap(find.byKey(const Key('setup-continue')));
      await tester.pumpAndSettle();
      await openChild(tester);
      await tester.enterText(find.byKey(const Key('child-name')), 'Mia');
      h.database.raw.execute(
        'INSERT INTO app_preferences(key,value) VALUES (?,?)',
        [
          'family-access-${h.controller.family!.householdId}',
          jsonEncode({'role': 'revoked', 'permission': null}),
        ],
      );
      h.controller.refresh();
      await tester.pumpAndSettle();
      expect(
        find.text('Family access changed. Return to the calendar.'),
        findsWidgets,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('child-save')))
            .onPressed,
        isNull,
      );
      expect(h.repository.load()!.children, isEmpty);
      expect(
        h.database.raw.select(
          "SELECT 1 FROM outbox WHERE kind='child_created'",
        ),
        isEmpty,
      );
    },
  );

  testWidgets(
    'FAMILY-MOB-005 palette exhaustion requires explicit colour reuse',
    (tester) async {
      final h = await blank(tester);
      await tester.tap(find.byKey(const Key('setup-continue')));
      await tester.pumpAndSettle();
      for (final colour in ChildColours.values) {
        h.controller.addChild('Child ${colour.name}', colour.argb);
      }
      await openChild(tester);
      await tester.enterText(
        find.byKey(const Key('child-name')),
        'Additional child',
      );
      expect(
        find.textContaining('All suggested colours are in use'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('child-save')))
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.byKey(const Key('child-colour-teal')));
      await tester.tap(find.byKey(const Key('child-colour-teal')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('child-save')));
      await tester.pumpAndSettle();
      expect(h.repository.load()!.children, hasLength(7));
      expect(
        h.repository
            .load()!
            .children
            .singleWhere((c) => c.name == 'Additional child')
            .colorArgb,
        0xffb8e2dc,
      );
    },
  );

  testWidgets(
    'FAMILY-SYNC-001 shared colour selection reaches authorized encrypted receiver',
    (tester) async {
      final f = ChildSyncFixture(sodium);
      final controller = CalendarController(
        f.a.repository,
        timezone: 'America/Vancouver',
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        f.close();
      });
      await tester.pumpWidget(
        MaterialApp(home: CalendarScreen(controller: controller)),
      );
      await tester.tap(find.byTooltip('Add child'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('child-name')), 'Harper');
      await tester.ensureVisible(find.byKey(const Key('child-colour-teal')));
      await tester.tap(find.byKey(const Key('child-colour-teal')));
      await tester.ensureVisible(find.byKey(const Key('share-child-profile')));
      await tester.tap(find.byKey(const Key('share-child-profile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('child-save')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await f.a.sync();
        await f.b.sync();
      });
      final received = f.b.repository.load()!.children.single;
      expect(received.name, 'Harper');
      expect(received.colorArgb, 0xffb8e2dc);
      expect(
        f.operations
            .where((op) => op.resourceId == received.id)
            .every((op) => op.ciphertext.isNotEmpty),
        isTrue,
      );
    },
  );
}
