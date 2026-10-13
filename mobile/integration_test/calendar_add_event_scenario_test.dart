import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import '../test/support/sarti_test_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tz_data.initializeTimeZones);

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

    expect(find.text('Swimming'), findsOneWidget);
    expect(harness.controller.family!.events.single.childIds, hasLength(1));
    expect(harness.controller.family!.events.single.recurrence, isNotNull);
    expect(harness.reminders.scheduled, hasLength(1));
  });
}
