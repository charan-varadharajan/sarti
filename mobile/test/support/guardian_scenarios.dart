import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sarti_mobile/src/features/guardians/guardian_screen.dart';
import 'package:sarti_mobile/src/features/guardians/invitation_links.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_controller.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_screen.dart';
import 'package:sodium/sodium.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'guardian_fixture.dart';

void guardianScenarios() {
  late Sodium sodium;
  setUpAll(() async {
    sodium = await SodiumInit.init();
    tz_data.initializeTimeZones();
  });
  testWidgets(
    'GUARD-MOB-001 prepared QR share, acceptance, verified approval and encrypted calendar',
    (tester) async {
      final g = GuardianFixture(sodium);
      addTearDown(g.close);
      final child = g.f.a.repository.addChild(
        'Mia',
        0xff00ff00,
        cloudAlias: 'green-fox-1234',
      );
      final location = tz.getLocation('America/Vancouver');
      final now = tz.TZDateTime.now(location);
      CalendarController(g.f.a.repository, timezone: 'America/Vancouver').save(
        title: 'Swimming',
        localStart: now,
        durationMinutes: 60,
        childIds: [child.id],
      );
      await g.owner.refresh();
      String? shared, copied;
      await tester.pumpWidget(
        MaterialApp(
          home: GuardianScreen(
            coordinator: g.owner,
            share: (link, origin) async {
              shared = link;
              expect(origin.width, greaterThan(0));
            },
            copy: (link) async {
              copied = link;
            },
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('guardian-create-invitation')));
      await tester.pumpAndSettle();
      final qrFinder = find.byKey(const Key('guardian-invitation-qr'));
      final qr = tester.widget<QrImageView>(qrFinder);
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.descendant(
                      of: qrFinder,
                      matching: find.byType(CustomPaint),
                    ),
                  )
                  .painter!
              as QrPainter;
      // Compare the actual rendered QR with the expected token-only payload.
      // QrImageView deliberately does not expose its private data field.
      final expected = QrPainter(
        data: invitationLink(g.token),
        version: qr.version,
        errorCorrectionLevel: qr.errorCorrectionLevel,
        gapless: qr.gapless,
        eyeStyle: qr.eyeStyle,
        dataModuleStyle: qr.dataModuleStyle,
      );
      await tester.runAsync(() async {
        final actualImage = await painter.toImageData(224);
        final expectedImage = await expected.toImageData(224);
        expect(
          actualImage!.buffer.asUint8List(),
          orderedEquals(expectedImage!.buffer.asUint8List()),
        );
      });
      await tester.ensureVisible(find.byKey(const Key('guardian-share-link')));
      await tester.tap(find.byKey(const Key('guardian-share-link')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('guardian-copy-link')));
      await tester.pumpAndSettle();
      expect(shared, invitationLink(g.token));
      expect(copied, invitationLink(g.token));
      await tester.pumpWidget(
        MaterialApp(home: GuardianScreen(coordinator: g.guardian)),
      );
      await tester.enterText(
        find.byKey(const Key('guardian-invitation-input')),
        shared!,
      );
      await tester.tap(find.byKey(const Key('guardian-accept')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('guardian-own-code')), findsOneWidget);
      expect(g.f.b.repository.load(), isNull);
      expect(await g.f.b.keyGrants(), isEmpty);
      await g.owner.refresh();
      await tester.pumpWidget(
        MaterialApp(home: GuardianScreen(coordinator: g.owner)),
      );
      await tester.ensureVisible(find.text('Review and approve'));
      await tester.tap(find.text('Review and approve'));
      await tester.pumpAndSettle();
      expect(find.text(g.guardian.ownCode), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('guardian-approve')))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byKey(const Key('guardian-name')), 'Dad');
      await tester.ensureVisible(
        find.byKey(const Key('guardian-code-confirmation')),
      );
      await tester.tap(find.byKey(const Key('guardian-code-confirmation')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('guardian-approve')));
      await tester.tap(find.byKey(const Key('guardian-approve')));
      await tester.pumpAndSettle();
      expect(g.status, 'approved');
      await g.guardian.refresh();
      expect(g.guardian.ready, isTrue);
      expect(g.f.b.repository.load()!.events.single.title, 'Swimming');
      expect(g.f.b.repository.load()!.children.single.name, 'Mia');
      final controller = CalendarController(
        g.f.b.repository,
        timezone: 'America/Vancouver',
      );
      addTearDown(controller.dispose);
      final before = g.f.b.database.raw
          .select('SELECT COUNT(*) AS n FROM outbox')
          .single['n'];
      await tester.pumpWidget(
        MaterialApp(
          home: CalendarScreen(
            controller: controller,
            canWrite: false,
            canManageChildren: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FloatingActionButton, 'Event'), findsNothing);
      expect(find.byTooltip('Add child'), findsNothing);
      await tester.tap(find.byTooltip('Show agenda'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Event actions'), findsNothing);
      expect(
        g.f.b.database.raw
            .select('SELECT COUNT(*) AS n FROM outbox')
            .single['n'],
        before,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'GUARD-MOB-002 malformed invitation is bounded and sends no request',
    (tester) async {
      final g = GuardianFixture(sodium);
      addTearDown(g.close);
      await tester.pumpWidget(
        MaterialApp(home: GuardianScreen(coordinator: g.guardian)),
      );
      await tester.enterText(
        find.byKey(const Key('guardian-invitation-input')),
        'https://evil.example/?token=private',
      );
      await tester.tap(find.byKey(const Key('guardian-accept')));
      await tester.pumpAndSettle();
      expect(g.acceptCalls, 0);
      expect(find.textContaining('valid Sarti invitation'), findsOneWidget);
      expect(
        find.textContaining('evil.example'),
        findsOneWidget,
      ); // Only the parent's input field.
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'GUARD-MOB-003 expired QR is hidden and failed sharing keeps copy available',
    (tester) async {
      final g = GuardianFixture(sodium);
      addTearDown(g.close);
      await g.owner.refresh();
      await g.owner.create();
      await tester.pumpWidget(
        MaterialApp(
          home: GuardianScreen(
            coordinator: g.owner,
            share: (link, origin) async {
              throw StateError('Synthetic share failure.');
            },
          ),
        ),
      );
      await tester.ensureVisible(find.byKey(const Key('guardian-share-link')));
      await tester.tap(find.byKey(const Key('guardian-share-link')));
      await tester.pumpAndSettle();
      expect(
        find.text('Sharing unavailable. Copy the link instead.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('guardian-copy-link')), findsOneWidget);
      g.expires = DateTime.now().toUtc().subtract(const Duration(seconds: 1));
      await g.owner.refresh();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('guardian-invitation-qr')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
