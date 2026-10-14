import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/features/ai/cloud_alias.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/event_duration_input.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/family_management_screen.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/household_profiles_screen.dart';
import 'package:timezone/timezone.dart' as tz;

import 'sarti_test_harness.dart';

void profileNavigationScenarios() {
  testWidgets('PROFILE-NAV-001 More separates People and Pets', (tester) async {
    final f = SartiTestHarness.create();
    addTearDown(f.close);
    f.repository.saveParticipant(
      name: 'Pepper',
      kind: 'pet',
      colour: 0xffc5e1c1,
    );
    f.controller.refresh();
    await f.pumpCalendar(tester);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('People'), findsOneWidget);
    expect(find.text('Pets'), findsOneWidget);
    await tester.tap(find.text('People'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('add-adult')), findsOneWidget);
    expect(find.byKey(const Key('people-add-child')), findsOneWidget);
    expect(find.byKey(const Key('add-pet')), findsNothing);
    expect(find.text('Pepper'), findsNothing);
    expect(find.text('Mia'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pets'));
    await tester.pumpAndSettle();
    expect(find.text('Pepper'), findsOneWidget);
    expect(find.byKey(const Key('add-pet')), findsOneWidget);
    expect(find.text('Mia'), findsNothing);
    expect(find.byKey(const Key('add-adult')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'GUARD-ENTRY-001 offline guardian action explains connection without changing membership',
    (tester) async {
      final f = SartiTestHarness.create();
      addTearDown(f.close);
      final before = f.repository.load()!.guardians.length;
      await tester.pumpWidget(
        MaterialApp(home: FamilyManagementScreen(controller: f.controller)),
      );
      await tester.tap(find.text('Invite or remove guardians'));
      await tester.pumpAndSettle();
      expect(find.text('Connect to invite adults'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('configured Sarti service'),
        ),
        findsOneWidget,
      );
      expect(f.repository.load()!.guardians, hasLength(before));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'GUARD-ENTRY-002 Add adult invokes invitation action without impersonating an adult',
    (tester) async {
      final f = SartiTestHarness.create();
      addTearDown(f.close);
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: HouseholdProfilesScreen(
            controller: f.controller,
            onGuardians: () => opened++,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('add-adult')));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(f.repository.load()!.participants, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('GUARD-ENTRY-003 nonadmin cannot add adults or pets', (
    tester,
  ) async {
    final f = SartiTestHarness.create();
    addTearDown(f.close);
    f.database.raw.execute(
      'INSERT INTO app_preferences(key,value) VALUES (?,?)',
      [
        'family-access-test-family-primary',
        '{"role":"guardian","permission":"read"}',
      ],
    );
    for (final pets in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          home: HouseholdProfilesScreen(
            controller: f.controller,
            petsOnly: pets,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('add-adult')), findsNothing);
      expect(find.byKey(const Key('people-add-child')), findsNothing);
      expect(find.byKey(const Key('add-pet')), findsNothing);
    }
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'ALIAS-AUTO-001 blank alias generates distinct encrypted child aliases',
    (tester) async {
      final f = SartiTestHarness.create();
      addTearDown(f.close);
      await tester.pumpWidget(
        MaterialApp(home: HouseholdProfilesScreen(controller: f.controller)),
      );
      for (final name in ['Robin', 'Casey']) {
        await tester.tap(find.byKey(const Key('people-add-child')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('child-name')), name);
        await tester.enterText(find.byKey(const Key('child-alias')), '   ');
        await tester.tap(find.widgetWithText(FilledButton, 'Add'));
        await tester.pumpAndSettle();
      }
      final children = f.repository.load()!.children;
      expect(children, hasLength(4));
      expect(children.map((c) => c.cloudAlias).toSet(), hasLength(4));
      for (final child in children) {
        expect(
          CloudAlias.validate(child.cloudAlias, childName: child.name),
          child.cloudAlias,
        );
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'EVENT-ENTRY-001 FAB offers Describe with local unsaved preview',
    (tester) async {
      final f = SartiTestHarness.create();
      addTearDown(f.close);
      await f.pumpCalendar(tester);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.text('Enter event details'), findsOneWidget);
      await tester.tap(find.text('Describe an event'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextField, 'Event description'),
        findsOneWidget,
      );
      expect(f.repository.load()!.events, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'DURATION-UI-001 hours and minutes validate and save exact duration',
    (tester) async {
      final f = SartiTestHarness.create();
      addTearDown(f.close);
      await f.pumpCalendar(tester);
      await f.openAddEvent(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Karate');
      await tester.enterText(
        find.byKey(const Key('event-duration-hours')),
        '2',
      );
      await tester.enterText(find.byKey(const Key('event-duration')), '75');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byKey(const Key('event-duration')), '30');
      await tester.pump();
      expect(find.textContaining('Ends:'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(f.repository.load()!.events.single.durationMinutes, 150);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'DURATION-END-001 compact end preserves next-day and DST context',
    (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      final zone = tz.getLocation('America/Vancouver');
      expect(
        formatEventEnd(context, tz.TZDateTime(zone, 2026, 10, 14, 12), 120),
        '2:00 PM',
      );
      expect(
        formatEventEnd(context, tz.TZDateTime(zone, 2026, 10, 14, 23), 120),
        contains('Oct 15'),
      );
      expect(
        formatEventEnd(context, tz.TZDateTime(zone, 2026, 3, 8, 1, 30), 60),
        '3:30 AM PDT',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
