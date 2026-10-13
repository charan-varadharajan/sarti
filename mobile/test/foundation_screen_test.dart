import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import 'support/sarti_test_harness.dart';

void main() {
  setUpAll(tz_data.initializeTimeZones);
  testWidgets('ONB-MOB-001 progressive onboarding reaches the calendar', (
    tester,
  ) async {
    final harness = SartiTestHarness.create(
      fixture: SartiTestFixture.blankDevice,
    );
    addTearDown(harness.close);
    await harness.pumpCalendar(tester);

    expect(
      find.text(
        'Start with the calendar. You can add family details as you go.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Create family'));
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Week'), findsOneWidget);
    expect(find.text('Month'), findsOneWidget);
  });

  testWidgets('CAL-MOB-001 adds a recurring event from prepared data', (
    tester,
  ) async {
    final harness = SartiTestHarness.create();
    addTearDown(harness.close);
    await harness.pumpCalendar(tester);

    await harness.openAddEvent(tester);
    await tester.enterText(find.byType(TextField).first, 'Swimming');
    await tester.tap(find.text('Repeat weekly'));
    final miaId = harness.controller.family!.children
        .firstWhere((child) => child.name == 'Mia')
        .id;
    final mia = find.byKey(Key('event-child-$miaId'));
    await tester.drag(
      find.byKey(const Key('event-editor-scroll')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    await tester.tap(mia);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Show agenda'));
    await tester.pumpAndSettle();

    // The editor defaults to one hour from now, which can be tomorrow.
    // Navigate to the saved date instead of assuming it is still visible today.
    final period = find.byKey(const Key('calendar-period'));
    final savedDate = MaterialLocalizations.of(tester.element(period))
        .formatFullDate(harness.controller.family!.events.single.localStart);
    if (tester.widget<Text>(period).data != savedDate) {
      await tester.tap(find.byTooltip('Next period'));
      await tester.pumpAndSettle();
    }
    expect(tester.widget<Text>(period).data, savedDate);
    expect(find.text('Swimming'), findsOneWidget);
    expect(find.textContaining('weekly'), findsOneWidget);
    expect(harness.controller.family!.events.single.childIds, hasLength(1));
    expect(harness.controller.family!.events.single.recurrence, isNotNull);
    expect(harness.reminders.scheduled, hasLength(1));
  });
}
