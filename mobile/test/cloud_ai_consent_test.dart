import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/core/ids.dart';
import 'package:sarti_mobile/src/features/ai/cloud_ai_consent.dart';
import 'package:sarti_mobile/src/features/ai/gemini_ai_provider.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_controller.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_screen.dart';
import 'package:timezone/data/latest.dart' as tz_data;

void main() {
  setUpAll(tz_data.initializeTimeZones);

  test('cloud consent defaults off and persists reversible choice', () {
    final database = SartiDatabase.open(':memory:', Uint8List(32));
    addTearDown(database.close);
    final store = CloudAiConsentStore(database);
    final controller = CloudAiConsentController(store);

    expect(controller.enabled, isFalse);
    controller.setEnabled(true);
    expect(CloudAiConsentController(store).enabled, isTrue);
    controller.setEnabled(false);
    expect(CloudAiConsentController(store).enabled, isFalse);
  });

  test(
    'CLOUD-CONSENT-002 old disclosure consent does not enable version 3',
    () {
      final database = SartiDatabase.open(':memory:', Uint8List(32));
      addTearDown(database.close);
      database.raw.execute(
        "INSERT INTO app_preferences(key,value) VALUES ('cloud_ai_consent_v2','enabled')",
      );
      final store = CloudAiConsentStore(database);
      expect(store.enabled, isFalse);
      store.setEnabled(true);
      expect(store.enabled, isTrue);
      store.setEnabled(false);
      expect(store.enabled, isFalse);
    },
  );

  test('cloud gate constructs Gemini only after explicit consent', () {
    final database = SartiDatabase.open(':memory:', Uint8List(32));
    addTearDown(database.close);
    final consent = CloudAiConsentController(CloudAiConsentStore(database));
    var constructions = 0;
    final gate = CloudAiGate(
      consent: consent,
      available: true,
      providerFactory: () {
        constructions++;
        return GeminiAiProvider.broker((_) async => null);
      },
    );

    expect(gate.createProvider(), isNull);
    expect(constructions, 0);
    consent.setEnabled(true);
    expect(gate.createProvider(), isNotNull);
    expect(constructions, 1);
  });

  test('cloud gate remains unavailable without provider configuration', () {
    final database = SartiDatabase.open(':memory:', Uint8List(32));
    addTearDown(database.close);
    final consent = CloudAiConsentController(CloudAiConsentStore(database));
    consent.setEnabled(true);
    final gate = CloudAiGate(
      consent: consent,
      available: false,
      providerFactory: () => GeminiAiProvider.broker((_) async => null),
    );

    expect(gate.available, isFalse);
    expect(gate.createProvider(), isNull);
  });

  testWidgets(
    'CLOUD-CONSENT-MOB-001 privacy dialog discloses cloud data and records opt-in',
    (tester) async {
      final database = SartiDatabase.open(':memory:', Uint8List(32));
      addTearDown(database.close);
      final repository = CalendarRepository(database, deviceId: newId());
      repository.createFamily(name: 'Family', ownerName: 'Parent');
      final calendar = CalendarController(
        repository,
        timezone: 'America/Vancouver',
      );
      final consent = CloudAiConsentController(CloudAiConsentStore(database));

      await tester.pumpWidget(
        MaterialApp(
          home: CalendarScreen(controller: calendar, cloudAiConsent: consent),
        ),
      );
      await tester.tap(find.byTooltip('Privacy & AI'));
      await tester.pumpAndSettle();

      expect(find.text('Privacy & AI'), findsOneWidget);
      expect(
        find.textContaining('pseudonymization, not anonymization'),
        findsOneWidget,
      );
      expect(find.textContaining('local deterministic parser'), findsOneWidget);
      expect(find.textContaining('fresh temporary labels'), findsOneWidget);
      expect(
        find.textContaining('Schedules can still be sensitive'),
        findsOneWidget,
      );
      expect(find.textContaining('does not guarantee'), findsOneWidget);
      expect(find.textContaining('A repeated alias may link'), findsNothing);
      expect(consent.enabled, isFalse);

      await tester.ensureVisible(find.byType(Switch));
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(consent.enabled, isTrue);
      expect(find.text('Enabled on this device'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(consent.enabled, isFalse);
      expect(repository.load()!.events, isEmpty);
      expect(database.raw.select('SELECT 1 FROM events'), isEmpty);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Privacy & AI'), findsOneWidget);
    },
  );
}
