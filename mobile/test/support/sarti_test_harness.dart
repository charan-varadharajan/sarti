import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/features/ai/native_ai_provider.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/features/calendar/data/reminder_scheduler.dart';
import 'package:sarti_mobile/src/features/calendar/domain/calendar_event.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_controller.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_screen.dart';

/// Named, reusable fixture states from docs/testing/TEST-SCENARIOS.md.
enum SartiTestFixture { blankDevice, calendarReady }

/// A disposable logical device and encrypted local database for functional
/// widget and emulator tests. It never uses production credentials or data.
class SartiTestHarness {
  SartiTestHarness._({
    required this.fixture,
    required this.database,
    required this.repository,
    required this.controller,
    required this.reminders,
  });

  static const deviceId = 'test-device-primary';
  static const timezone = 'America/Vancouver';

  final SartiTestFixture fixture;
  final SartiDatabase database;
  final CalendarRepository repository;
  final CalendarController controller;
  final TestReminderScheduler reminders;

  static SartiTestHarness create({
    SartiTestFixture fixture = SartiTestFixture.calendarReady,
    DateTime Function()? clock,
    String displayTimezone = timezone,
  }) {
    final database = SartiDatabase.open(':memory:', Uint8List(32));
    final repository = CalendarRepository(database, deviceId: deviceId);
    final reminders = TestReminderScheduler();
    final controller = CalendarController(
      repository,
      timezone: displayTimezone,
      clock: clock ?? DateTime.now,
      reminders: reminders,
    );
    final harness = SartiTestHarness._(
      fixture: fixture,
      database: database,
      repository: repository,
      controller: controller,
      reminders: reminders,
    );
    if (fixture == SartiTestFixture.calendarReady) {
      harness._seedCalendarReady();
    }
    return harness;
  }

  void _seedCalendarReady() {
    repository.createFamily(
      name: 'Test family',
      ownerName: 'Alex',
      familyId: 'test-family-primary',
      calendarResourceId: 'test-calendar-primary',
    );
    repository.addChild('Mia', 0xFF8E6CEF, cloudAlias: 'hanging-frog-4821');
    repository.addChild('Jithu', 0xFF2E7D32, cloudAlias: 'bright-otter-7314');
    controller.refresh();
  }

  Future<void> pumpCalendar(
    WidgetTester tester, {
    NativeEventAiProvider? nativeAi,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CalendarScreen(controller: controller, nativeAi: nativeAi),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openAddEvent(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Event'));
    await tester.pumpAndSettle();
  }

  Future<void> openNaturalLanguageEvent(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Add with natural language'));
    await tester.pumpAndSettle();
  }

  void close() => database.close();
}

class TestReminderScheduler implements ReminderScheduler {
  final List<CalendarEvent> scheduled = [];
  final List<String> cancelledEventIds = [];

  @override
  Future<void> cancelFor(String eventId) async {
    cancelledEventIds.add(eventId);
  }

  @override
  Future<void> replaceFor(CalendarEvent event) async {
    scheduled.add(event);
  }
}
