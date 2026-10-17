import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import '../test/support/sarti_test_harness.dart';
import '../test/support/family_setup_scenarios.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tz_data.initializeTimeZones);
  familySetupScenarios();

  testWidgets('CAL-MOB-001 adds an event from a prepared calendar', (
    tester,
  ) async {
    final harness = SartiTestHarness.create();
    addTearDown(harness.close);

    await harness.pumpCalendar(tester);
    expect(find.text('Test family'), findsOneWidget);
    expect(find.text('Mia'), findsNothing);

    await harness.openAddEvent(tester);
    await tester.enterText(find.byType(TextField).first, 'Swimming');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final repeat = find.widgetWithText(SwitchListTile, 'Repeat weekly');
    await Scrollable.ensureVisible(tester.element(repeat), alignment: 0.2);
    await tester.pumpAndSettle();
    await tester.tap(repeat);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(repeat).value, isTrue);
    final miaId = harness.controller.family!.children
        .firstWhere((child) => child.name == 'Mia')
        .id;
    final mia = find.byKey(Key('event-child-$miaId'));
    await tester.drag(
      find.byKey(const Key('event-editor-scroll')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(mia);
    await tester.pumpAndSettle();
    await tester.tap(mia);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Show agenda'));
    await tester.pumpAndSettle();

    // The one-hour default can cross midnight. Inspect the saved date, as the
    // matching widget scenario already does, rather than assuming today.
    final period = find.byKey(const Key('calendar-period'));
    final savedDate = MaterialLocalizations.of(tester.element(period))
        .formatFullDate(harness.controller.family!.events.single.localStart);
    if (tester.widget<Text>(period).data != savedDate) {
      await tester.tap(find.byTooltip('Next period'));
      await tester.pumpAndSettle();
    }
    expect(tester.widget<Text>(period).data, savedDate);
    expect(find.text('Swimming'), findsOneWidget);
    expect(harness.controller.family!.events.single.childIds, hasLength(1));
    expect(harness.controller.family!.events.single.recurrence, isNotNull);
    expect(harness.reminders.scheduled, hasLength(1));
  });
}
