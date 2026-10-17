import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/core/crypto/device_key_store.dart';
import 'package:sarti_mobile/src/core/network/sarti_api.dart';
import 'package:sarti_mobile/src/core/ids.dart';
import 'package:sarti_mobile/src/features/ai/native_ai_provider.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_controller.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_screen.dart';
import 'package:sarti_mobile/src/features/email/email_suggestion_inbox.dart';
import 'package:sodium/sodium.dart';
import 'package:timezone/data/latest.dart' as tz_data;

void main() {
  setUpAll(tz_data.initializeTimeZones);

  testWidgets('ambiguous time requires an explicit AM or PM choice', (
    tester,
  ) async {
    final database = SartiDatabase.open(':memory:', Uint8List(32));
    addTearDown(database.close);
    final repository = CalendarRepository(database, deviceId: newId());
    repository.createFamily(name: 'Family', ownerName: 'Parent');
    repository.addChild('Mia', 0xFF8E6CEF);
    final controller = CalendarController(
      repository,
      timezone: 'America/Vancouver',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CalendarScreen(
          controller: controller,
          nativeAi: NativeEventAiProvider(_UnavailableBridge()),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Add with natural language'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Event description'),
      'Mia has swimming Tuesday at 5',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Preview'));
    await tester.pumpAndSettle();

    expect(find.text('Missing — choose a time'), findsOneWidget);
    expect(
      find.text('Is that AM or PM? Choose the intended time before adding it.'),
      findsOneWidget,
    );
    final addButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Add to calendar'),
    );
    expect(addButton.onPressed, isNull);
    expect(repository.load()!.events, isEmpty);
  });

  testWidgets('natural-language event requires review and supports undo', (
    tester,
  ) async {
    final database = SartiDatabase.open(':memory:', Uint8List(32));
    addTearDown(database.close);
    final repository = CalendarRepository(database, deviceId: newId());
    repository.createFamily(name: 'Family', ownerName: 'Parent');
    repository.addChild('Mia', 0xFF8E6CEF);
    final controller = CalendarController(
      repository,
      timezone: 'America/Vancouver',
    );
    final provider = NativeEventAiProvider(_UnavailableBridge());

    await tester.pumpWidget(
      MaterialApp(
        home: CalendarScreen(controller: controller, nativeAi: provider),
      ),
    );
    await tester.tap(find.byTooltip('Add with natural language'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Event description'),
      'Mia has swimming tomorrow at 5pm',
    );
    await tester.pump();
    final previewButton = find.widgetWithText(FilledButton, 'Preview');
    expect(tester.widget<FilledButton>(previewButton).onPressed, isNotNull);
    await tester.tap(previewButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Review suggestion'), findsOneWidget);
    expect(
      find.text('Nothing is saved until you approve this suggestion.'),
      findsOneWidget,
    );
    expect(repository.load()!.events, isEmpty);

    await tester.tap(find.text('Add to calendar'));
    await tester.pumpAndSettle();
    expect(repository.load()!.events.single.title, 'swimming');
    expect(repository.load()!.events.single.childIds, hasLength(1));

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(repository.load()!.events, hasLength(1));
    expect(find.text('Edit event'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(repository.load()!.events, isEmpty);
  });

  testWidgets(
    'encrypted email stays a source-attributed proposal until approval',
    (tester) async {
      final database = SartiDatabase.open(':memory:', Uint8List(32));
      addTearDown(database.close);
      final repository = CalendarRepository(database, deviceId: newId());
      repository.createFamily(name: 'Family', ownerName: 'Parent');
      repository.addChild('Mia', 0xFF8E6CEF);
      final controller = CalendarController(
        repository,
        timezone: 'America/Vancouver',
      );
      final sodium = await SodiumInit.init();
      final box = sodium.crypto.box.keyPair();
      final signing = sodium.crypto.sign.keyPair();
      final keys = DeviceKeyMaterial(
        databaseKey: sodium.secureRandom(32),
        encryptionPublicKey: box.publicKey,
        encryptionSecretKey: box.secretKey,
        signingPublicKey: signing.publicKey,
        signingSecretKey: signing.secretKey,
        deviceId: 'device',
      );
      addTearDown(keys.dispose);
      final ciphertext = sodium.crypto.box.seal(
        message: Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'version': 2,
              'family_id': controller.family!.householdId,
              'suggestion_id': 'email-id',
              'sender': 'teacher@example.com',
              'subject': 'Mia has swimming tomorrow at 5pm',
              'body': '',
            }),
          ),
        ),
        publicKey: box.publicKey,
      );
      final dismissed = <String>[];
      final inbox = EmailSuggestionInbox(
        sodium: sodium,
        keys: keys,
        fetch: () async => [
          EncryptedEmailDelivery(
            familyId: controller.family!.householdId,
            suggestionId: 'email-id',
            ciphertext: ciphertext,
            receivedAt: DateTime.utc(2026, 10, 11),
            expiresAt: DateTime.utc(2026, 10, 18),
          ),
        ],
        dismissRemote: (id) async => dismissed.add(id),
      );
      await inbox.refresh();

      await tester.pumpWidget(
        MaterialApp(
          home: CalendarScreen(
            controller: controller,
            nativeAi: NativeEventAiProvider(_UnavailableBridge()),
            emailInbox: inbox,
          ),
        ),
      );
      await tester.tap(find.byTooltip('Email suggestions'));
      await tester.pumpAndSettle();
      expect(find.text('From teacher@example.com'), findsOneWidget);
      await tester.tap(find.text('Mia has swimming tomorrow at 5pm'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('Suggested from email by teacher@example.com'),
        findsOneWidget,
      );
      expect(repository.load()!.events, isEmpty);

      await tester.tap(find.text('Add to calendar'));
      await tester.pumpAndSettle();

      expect(repository.load()!.events.single.title, 'swimming');
      expect(dismissed, ['email-id']);
    },
  );
}

class _UnavailableBridge implements NativeAiBridge {
  @override
  Future<NativeAiAvailability> availability() async =>
      NativeAiAvailability.unsupported;

  @override
  Future<String> generate(String prompt) =>
      throw StateError('Fallback must not call native generation.');
}
