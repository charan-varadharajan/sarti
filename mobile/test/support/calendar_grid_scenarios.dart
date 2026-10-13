import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalender/kalender.dart' as k;
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_controller.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/family_calendar_view.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'sarti_test_harness.dart';

void calendarGridScenarios() {
  setUpAll(tz_data.initializeTimeZones);

  testWidgets(
    'CAL-GRID-MOB-001 prepared day/week/month navigation does not write',
    (tester) async {
      final harness = SartiTestHarness.create();
      addTearDown(harness.close);
      var range = CalendarRange.today;
      final now = tz.TZDateTime(
        tz.getLocation(SartiTestHarness.timezone),
        2026,
        10,
        12,
        9,
      );
      final mia = harness.controller.family!.children.first;
      harness.controller.save(
        title: 'Morning activity',
        localStart: now,
        durationMinutes: 60,
        childIds: [mia.id],
      );
      harness.controller.save(
        title: 'Long activity',
        localStart: now.add(const Duration(hours: 2)),
        durationMinutes: 120,
        childIds: harness.controller.family!.children
            .map((child) => child.id)
            .toList(),
      );
      final before = harness.database.raw
          .select('SELECT COUNT(*) AS n FROM outbox')
          .single['n'];
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Column(
                children: [
                  Row(
                    children: [
                      TextButton(
                        onPressed: () =>
                            setState(() => range = CalendarRange.week),
                        child: const Text('Week'),
                      ),
                      TextButton(
                        onPressed: () =>
                            setState(() => range = CalendarRange.month),
                        child: const Text('Month'),
                      ),
                    ],
                  ),
                  Expanded(
                    child: FamilyCalendarView(
                      family: harness.controller.family!,
                      range: range,
                      timezone: SartiTestHarness.timezone,
                      initialDate: now,
                      onEdit: (event) => opened.add(event.id),
                      onCancel: (_) {},
                      onDelete: (_) {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(k.MultiDayBody), findsOneWidget);
      final morning = find.text('Morning activity');
      final long = find.text('Long activity');
      expect(morning, findsOneWidget);
      expect(long, findsOneWidget);
      expect(
        tester.getTopLeft(long).dy,
        greaterThan(tester.getTopLeft(morning).dy),
      );
      final tiles = find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.key is ValueKey<String> &&
            (widget.key as ValueKey<String>).value.startsWith(
              'calendar-occurrence-',
            ),
      );
      final morningTile = find.ancestor(of: morning, matching: tiles);
      final longTile = find.ancestor(of: long, matching: tiles);
      expect(
        tester.getSize(longTile).height,
        greaterThan(tester.getSize(morningTile).height * 1.8),
      );
      await tester.tap(morning);
      expect(opened, hasLength(1));
      final interaction = tester
          .widget<k.KalenderView>(find.byType(k.KalenderView))
          .interaction!;
      expect(interaction.allowEventCreation, isFalse);
      expect(interaction.allowRescheduling, isFalse);
      expect(interaction.allowResizing, isFalse);
      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calendar-week-scroll')), findsOneWidget);
      final week =
          tester
                  .widget<k.KalenderView>(find.byType(k.KalenderView))
                  .kalenderController
                  .viewConfiguration
              as k.MultiDayViewConfiguration;
      expect(week.numberOfDays, 7);
      await tester.tap(find.text('Month'));
      await tester.pumpAndSettle();
      expect(find.byType(k.MonthBody), findsOneWidget);
      await tester.tap(find.byTooltip('Show agenda'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calendar-agenda')), findsOneWidget);
      await tester.tap(find.byTooltip('Next period'));
      await tester.pumpAndSettle();
      expect(find.text('No events yet'), findsOneWidget);
      await tester.tap(find.byTooltip('Previous period'));
      await tester.pumpAndSettle();
      expect(find.text('Morning activity'), findsOneWidget);
      expect(
        harness.database.raw
            .select('SELECT COUNT(*) AS n FROM outbox')
            .single['n'],
        before,
      );
      expect(harness.controller.family!.events, hasLength(2));
    },
  );

  testWidgets(
    'CAL-GRID-MOB-002 overlaps remain separate and empty grids retain axes',
    (tester) async {
      final harness = SartiTestHarness.create();
      addTearDown(harness.close);
      final day = tz.TZDateTime(
        tz.getLocation(SartiTestHarness.timezone),
        2026,
        10,
        12,
        9,
      );
      for (final title in ['Overlap A', 'Overlap B']) {
        harness.controller.save(
          title: title,
          localStart: day,
          durationMinutes: 120,
          childIds: const [],
        );
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FamilyCalendarView(
              family: harness.controller.family!,
              range: CalendarRange.today,
              timezone: SartiTestHarness.timezone,
              initialDate: day,
              onEdit: (_) {},
              onCancel: (_) {},
              onDelete: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Overlap A')).dx,
        isNot(tester.getTopLeft(find.text('Overlap B')).dx),
      );
      expect(
        tester.getTopLeft(find.text('Overlap A')).dy,
        tester.getTopLeft(find.text('Overlap B')).dy,
      );
      await tester.tap(find.byTooltip('Next period'));
      await tester.pumpAndSettle();
      expect(find.byType(k.MultiDayBody), findsOneWidget);
      expect(find.text('Overlap A'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'CAL-GRID-MOB-003 narrow month supports large text and agenda labels',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final harness = SartiTestHarness.create();
      addTearDown(harness.close);
      final day = tz.TZDateTime(
        tz.getLocation(SartiTestHarness.timezone),
        2026,
        10,
        12,
        9,
      );
      harness.controller.save(
        title: 'Shared activity',
        localStart: day,
        durationMinutes: 120,
        childIds: harness.controller.family!.children
            .map((child) => child.id)
            .toList(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(390, 844),
              textScaler: TextScaler.linear(1.6),
            ),
            child: Scaffold(
              body: FamilyCalendarView(
                family: harness.controller.family!,
                range: CalendarRange.month,
                timezone: SartiTestHarness.timezone,
                initialDate: day,
                onEdit: (_) {},
                onCancel: (_) {},
                onDelete: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(k.MonthBody), findsOneWidget);
      await tester.tap(find.byTooltip('Show agenda'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Mia, Jithu'), findsOneWidget);
      expect(find.textContaining('09:00–11:00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
