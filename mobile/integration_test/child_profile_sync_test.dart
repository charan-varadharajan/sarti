import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sarti_mobile/src/features/calendar/domain/calendar_event.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_controller.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_screen.dart';
import 'package:sodium/sodium.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../test/support/child_sync_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'CHILD-NATIVE-001 prepared devices sync encrypted child labels and colours',
    (tester) async {
      tz_data.initializeTimeZones();
      final fixture = ChildSyncFixture(await SodiumInit.init());
      addTearDown(fixture.close);
      final controller = CalendarController(
        fixture.a.repository,
        timezone: 'America/Vancouver',
      );
      addTearDown(controller.dispose);
      // Both logical devices and family prerequisites exist before entering UI.
      await tester.pumpWidget(
        MaterialApp(home: CalendarScreen(controller: controller)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add child'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Mia');
      await tester.tap(find.byKey(const Key('share-child-profile')));
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      final child = controller.family!.children.single;
      final now = tz.TZDateTime.now(tz.getLocation('America/Vancouver'));
      fixture.a.repository.saveEvent(
        CalendarEvent(
          id: '44444444-4444-4444-8444-444444444444',
          householdId: fixture.familyId,
          calendarResourceId: fixture.calendarId,
          title: 'Swimming',
          localStart: DateTime(now.year, now.month, now.day, 17),
          timezone: 'America/Vancouver',
          durationMinutes: 60,
          childIds: [child.id],
          revision: 1,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      // Network work runs outside the test's fake clock. Native SQLCipher and
      // libsodium execute; relay/authentication remain controlled fixtures.
      await tester.runAsync(() async {
        await fixture.a.sync();
        await fixture.b.sync();
      });
      final receiving = CalendarController(
        fixture.b.repository,
        timezone: 'America/Vancouver',
      );
      addTearDown(receiving.dispose);
      await tester.pumpWidget(
        MaterialApp(home: CalendarScreen(controller: receiving)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Show agenda'));
      await tester.pumpAndSettle();
      expect(find.text('Swimming'), findsOneWidget);
      expect(find.textContaining('Mia'), findsOneWidget);
      expect(
        fixture.b.database.raw.select('PRAGMA cipher_version'),
        isNotEmpty,
      );
      expect(
        fixture.b.database.resourceKey(child.id, 1),
        fixture.a.database.resourceKey(child.id, 1),
      );
      expect(
        tester
            .widget<CircleAvatar>(find.byType(CircleAvatar).first)
            .backgroundColor,
        const Color(0xff8e6cef),
      );
      await tester.runAsync(() async {
        expect((await fixture.b.sync()).applied, 0);
      });
    },
  );
}
