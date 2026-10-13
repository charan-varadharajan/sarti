import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalender/kalender.dart' as k;
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_controller.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/family_calendar_view.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'sarti_test_harness.dart';

void calendarTodayScenarios() {
  setUpAll(tz_data.initializeTimeZones);

  Future<SartiTestHarness> prepare(
    WidgetTester tester, {
    DateTime? instant,
    String timezone = SartiTestHarness.timezone,
  }) async {
    final now = instant ?? DateTime.utc(2026, 10, 13, 16);
    final h = SartiTestHarness.create(
      clock: () => now,
      displayTimezone: timezone,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      h.controller.dispose();
      h.close();
    });
    final local = tz.TZDateTime.from(now, tz.getLocation(timezone));
    for (final entry in {
      -1: 'Past activity',
      0: 'Current activity',
      1: 'Future activity',
    }.entries) {
      h.controller.save(
        title: entry.value,
        localStart: tz.TZDateTime(
          local.location,
          local.year,
          local.month,
          local.day + entry.key,
          9,
        ),
        durationMinutes: 60,
        childIds: const [],
      );
    }
    await h.pumpCalendar(tester);
    return h;
  }

  void expectToday(WidgetTester tester, SartiTestHarness h) {
    final local = tz.TZDateTime.from(
      h.controller.clock(),
      tz.getLocation(h.controller.timezone),
    );
    final context = tester.element(find.byType(FamilyCalendarView));
    expect(
      tester.widget<Text>(find.byKey(const Key('calendar-period'))).data,
      MaterialLocalizations.of(context).formatFullDate(local),
    );
    expect(h.controller.range, CalendarRange.today);
    expect(
      tester
          .widget<SegmentedButton<CalendarRange>>(
            find.byType(SegmentedButton<CalendarRange>),
          )
          .selected,
      {CalendarRange.today},
    );
    final range = tester
        .widget<k.KalenderView>(find.byType(k.KalenderView))
        .kalenderController
        .visibleDateTimeRange
        .value;
    final start = tz.TZDateTime.from(range.start, local.location);
    expect(
      [start.year, start.month, start.day],
      [local.year, local.month, local.day],
    );
    expect(range.start.isAfter(local), isFalse);
    expect(range.end.isAfter(local), isTrue);
  }

  List<Map<String, Object?>> persisted(SartiTestHarness h) => [
    for (final row in h.database.raw.select(
      'SELECT * FROM outbox ORDER BY operation_id',
    ))
      Map<String, Object?>.from(row),
  ];

  testWidgets(
    'CAL-TODAY-MOB-001 repeated selected Today returns from past/future without writes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final h = await prepare(tester);
      final before = persisted(h);
      expectToday(tester, h);
      for (final tooltip in [
        'Previous period',
        'Next period',
        'Previous period',
      ]) {
        await tester.tap(find.byTooltip(tooltip));
        await tester.pumpAndSettle();
        expect(find.text('Current activity'), findsNothing);
        await tester.tap(find.text('Today'));
        await tester.pumpAndSettle();
        expectToday(tester, h);
        expect(find.text('Current activity'), findsOneWidget);
      }
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      expectToday(tester, h);
      expect(persisted(h), before);
      expect(h.controller.family!.events, hasLength(3));
    },
  );

  testWidgets(
    'CAL-TODAY-MOB-002 Today from week/month resets date and retains agenda',
    (tester) async {
      final h = await prepare(tester);
      final before = persisted(h);
      await tester.tap(find.byTooltip('Show agenda'));
      await tester.pumpAndSettle();
      for (final mode in ['Week', 'Month']) {
        await tester.tap(find.text(mode));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Next period'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Today'));
        await tester.pumpAndSettle();
        expect(h.controller.range, CalendarRange.today);
        expect(find.byTooltip('Show calendar grid'), findsOneWidget);
        expect(find.text('Current activity'), findsOneWidget);
        expect(find.text('Past activity'), findsNothing);
        expect(find.text('Future activity'), findsNothing);
        final local = tz.TZDateTime.from(
          h.controller.clock(),
          tz.getLocation(h.controller.timezone),
        );
        expect(
          tester.widget<Text>(find.byKey(const Key('calendar-period'))).data,
          MaterialLocalizations.of(
            tester.element(find.byType(FamilyCalendarView)),
          ).formatFullDate(local),
        );
      }
      await tester.tap(find.byTooltip('Show calendar grid'));
      await tester.pumpAndSettle();
      expectToday(tester, h);
      expect(persisted(h), before);
    },
  );

  testWidgets('CAL-TODAY-MOB-003 toolbar today keeps week/month layout', (
    tester,
  ) async {
    final h = await prepare(tester);
    final before = persisted(h);
    for (final mode in {
      CalendarRange.week: 'Week',
      CalendarRange.month: 'Month',
    }.entries) {
      await tester.tap(find.text(mode.value));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Previous period'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Go to today'));
      await tester.pumpAndSettle();
      expect(h.controller.range, mode.key);
      final range = tester
          .widget<k.KalenderView>(find.byType(k.KalenderView))
          .kalenderController
          .visibleDateTimeRange
          .value;
      expect(range.start.isAfter(h.controller.clock()), isFalse);
      expect(range.end.isAfter(h.controller.clock()), isTrue);
    }
    expect(persisted(h), before);
  });

  final zones = {
    'UTC-ahead': ('Pacific/Kiritimati', DateTime.utc(2026, 10, 13, 12, 30)),
    'UTC-behind': ('Pacific/Honolulu', DateTime.utc(2026, 10, 13, 0, 30)),
    'spring-DST': ('America/Vancouver', DateTime.utc(2026, 3, 8, 12)),
    'fall-DST': ('America/Vancouver', DateTime.utc(2026, 11, 1, 12)),
  };
  for (final zone in zones.entries) {
    testWidgets('CAL-TODAY-TZ-001 ${zone.key} uses display-zone date', (
      tester,
    ) async {
      final h = await prepare(
        tester,
        timezone: zone.value.$1,
        instant: zone.value.$2,
      );
      final before = persisted(h);
      await tester.tap(find.byTooltip('Next period'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      expectToday(tester, h);
      expect(persisted(h), before);
    });
  }
}
