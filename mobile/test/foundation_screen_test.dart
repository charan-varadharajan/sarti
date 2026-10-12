import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/core/ids.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/features/calendar/data/reminder_scheduler.dart';
import 'package:sarti_mobile/src/features/calendar/domain/calendar_event.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_controller.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_screen.dart';
import 'package:timezone/data/latest.dart' as tz_data;

void main() {
  setUpAll(tz_data.initializeTimeZones);
  testWidgets('progressive onboarding creates a recurring assigned event', (
    tester,
  ) async {
    final database = SartiDatabase.open(':memory:', Uint8List(32));
    addTearDown(database.close);
    final reminders = _FakeReminders();
    final controller = CalendarController(
      CalendarRepository(database, deviceId: newId()),
      timezone: 'America/Vancouver',
      reminders: reminders,
    );
    await tester.pumpWidget(
      MaterialApp(home: CalendarScreen(controller: controller)),
    );

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

    await tester.tap(find.byTooltip('Add child'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Mia');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Event'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Swimming');
    await tester.tap(find.text('Repeat weekly'));
    await tester.tap(find.text('Mia'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Swimming'), findsOneWidget);
    expect(find.textContaining('weekly'), findsOneWidget);
    expect(controller.family!.events.single.childIds, hasLength(1));
    expect(controller.family!.events.single.recurrence, isNotNull);
    expect(reminders.scheduled, hasLength(1));
  });
}

class _FakeReminders implements ReminderScheduler {
  final List<CalendarEvent> scheduled = [];

  @override
  Future<void> cancelFor(String eventId) async {}

  @override
  Future<void> replaceFor(CalendarEvent event) async => scheduled.add(event);
}
