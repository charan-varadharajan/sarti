import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/core/ids.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_controller.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_screen.dart';
import 'package:timezone/data/latest.dart' as zones;
import 'package:sarti_mobile/src/core/crypto/device_key_store.dart';
import 'package:sarti_mobile/src/core/network/sarti_api.dart';
import 'package:sarti_mobile/src/features/email/email_suggestion_inbox.dart';
import 'package:sodium/sodium.dart';

void main() {
  test(
    'decrypts device-sealed email and dismisses only by opaque id',
    () async {
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
      final plaintext = utf8.encode(
        jsonEncode({
          'version': 2,
          'family_id': '11111111-1111-4111-8111-111111111111',
          'suggestion_id': 'suggestion',
          'sender': 'teacher@example.com',
          'subject': 'Swimming Tuesday at 5 PM',
          'body': 'Please review this schedule.',
          'received_at': '2026-10-11T12:00:00Z',
        }),
      );
      final delivery = EncryptedEmailDelivery(
        familyId: '11111111-1111-4111-8111-111111111111',
        suggestionId: 'suggestion',
        ciphertext: sodium.crypto.box.seal(
          message: Uint8List.fromList(plaintext),
          publicKey: box.publicKey,
        ),
        receivedAt: DateTime.utc(2026, 10, 11, 12),
        expiresAt: DateTime.utc(2026, 10, 18, 12),
      );
      final dismissed = <String>[];
      final inbox = EmailSuggestionInbox(
        sodium: sodium,
        keys: keys,
        fetch: () async => [delivery],
        dismissRemote: (id) async => dismissed.add(id),
      );

      await inbox.refresh();

      expect(inbox.suggestions, hasLength(1));
      expect(inbox.suggestions.single.sender, 'teacher@example.com');
      expect(
        inbox.suggestions.single.interpretationInput,
        contains('Swimming Tuesday at 5 PM'),
      );

      await inbox.dismiss('suggestion');
      expect(dismissed, ['suggestion']);
      expect(inbox.suggestions, isEmpty);
    },
  );

  test('S5-EMAIL-001 sealed family binding isolates suggestions and rejects swapped/legacy deliveries', () async {
    final sodium = await SodiumInit.init();
    final box = sodium.crypto.box.keyPair(),
        signing = sodium.crypto.sign.keyPair();
    final keys = DeviceKeyMaterial(
      databaseKey: sodium.secureRandom(32),
      encryptionPublicKey: box.publicKey,
      encryptionSecretKey: box.secretKey,
      signingPublicKey: signing.publicKey,
      signingSecretKey: signing.secretKey,
      deviceId: 'device',
    );
    addTearDown(keys.dispose);
    const a = '11111111-1111-4111-8111-111111111111',
        b = '22222222-2222-4222-8222-222222222222';
    Uint8List seal(String id, String family, {int version = 2}) =>
        sodium.crypto.box.seal(
          message: Uint8List.fromList(
            utf8.encode(
              jsonEncode({
                'version': version,
                'family_id': family,
                'suggestion_id': id,
                'sender': 'synthetic@example.invalid',
                'subject': 'Scoped canary $family',
                'body': 'Review only',
              }),
            ),
          ),
          publicKey: box.publicKey,
        );
    EncryptedEmailDelivery delivery(
      String id,
      String family,
      Uint8List bytes,
    ) => EncryptedEmailDelivery(
      familyId: family,
      suggestionId: id,
      ciphertext: bytes,
      receivedAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(days: 1)),
    );
    final inbox = EmailSuggestionInbox(
      sodium: sodium,
      keys: keys,
      fetch: () async => [
        delivery('a', a, seal('a', a)),
        delivery('b', b, seal('b', b)),
        delivery('swapped', b, seal('swapped', a)),
        delivery('legacy', a, seal('legacy', a, version: 1)),
      ],
      dismissRemote: (_) async {},
    );
    addTearDown(inbox.dispose);
    await inbox.refresh();
    expect(inbox.suggestions, hasLength(2));
    expect(inbox.forHousehold(a).single.id, 'a');
    expect(inbox.forHousehold(b).single.id, 'b');
    expect(inbox.forHousehold('unknown'), isEmpty);
    await inbox.dismiss('a');
    expect(inbox.forHousehold(a), isEmpty);
    expect(inbox.forHousehold(b).single.id, 'b');
  });

  testWidgets(
    'S5-EMAIL-003 prepared email sheet stays in its household and stale selection cannot propose into another',
    (tester) async {
      zones.initializeTimeZones();
      final sodium = await SodiumInit.init();
      final db = SartiDatabase.open(':memory:', Uint8List(32));
      final repo = CalendarRepository(db, deviceId: newId());
      final a = repo.createFamily(name: 'A'), b = repo.createFamily(name: 'B');
      repo.selectHousehold(a.householdId);
      final c = CalendarController(repo, timezone: 'Etc/UTC');
      final box = sodium.crypto.box.keyPair(),
          signing = sodium.crypto.sign.keyPair();
      final keys = DeviceKeyMaterial(
        databaseKey: sodium.secureRandom(32),
        encryptionPublicKey: box.publicKey,
        encryptionSecretKey: box.secretKey,
        signingPublicKey: signing.publicKey,
        signingSecretKey: signing.secretKey,
        deviceId: 'device',
      );
      final inbox = EmailSuggestionInbox(
        sodium: sodium,
        keys: keys,
        fetch: () async => [
          for (final f in [a, b])
            EncryptedEmailDelivery(
              familyId: f.householdId,
              suggestionId: f.householdId,
              ciphertext: sodium.crypto.box.seal(
                message: Uint8List.fromList(
                  utf8.encode(
                    jsonEncode({
                      'version': 2,
                      'family_id': f.householdId,
                      'suggestion_id': f.householdId,
                      'sender': 'synthetic@example.invalid',
                      'subject': 'Only household ${f.name}',
                      'body': 'Swimming tomorrow at noon',
                    }),
                  ),
                ),
                publicKey: box.publicKey,
              ),
              receivedAt: DateTime.now(),
              expiresAt: DateTime.now().add(const Duration(days: 1)),
            ),
        ],
        dismissRemote: (_) async {},
      );
      addTearDown(() {
        inbox.dispose();
        keys.dispose();
        c.dispose();
        db.close();
      });
      await inbox.refresh();
      await tester.pumpWidget(
        MaterialApp(
          home: CalendarScreen(controller: c, emailInbox: inbox),
        ),
      );
      await tester.tap(find.byTooltip('Email suggestions'));
      await tester.pumpAndSettle();
      expect(find.text('Only household A'), findsOneWidget);
      expect(find.text('Only household B'), findsNothing);
      c.selectHousehold(b.householdId);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Only household A'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(db.raw.select('SELECT * FROM events'), isEmpty);
      await tester.tap(find.byTooltip('Email suggestions'));
      await tester.pumpAndSettle();
      expect(find.text('Only household A'), findsNothing);
      expect(find.text('Only household B'), findsOneWidget);
      expect(inbox.suggestions, hasLength(2));
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('drops malformed, tampered, and mismatched deliveries', () async {
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
    final mismatched = sodium.crypto.box.seal(
      message: Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'version': 2,
            'family_id': '11111111-1111-4111-8111-111111111111',
            'suggestion_id': 'other',
            'sender': 'sender@example.com',
            'subject': '',
            'body': '',
          }),
        ),
      ),
      publicKey: box.publicKey,
    );
    final inbox = EmailSuggestionInbox(
      sodium: sodium,
      keys: keys,
      fetch: () async => [
        EncryptedEmailDelivery(
          familyId: '11111111-1111-4111-8111-111111111111',
          suggestionId: 'expected',
          ciphertext: mismatched,
          receivedAt: DateTime.now(),
          expiresAt: DateTime.now().add(const Duration(days: 1)),
        ),
        EncryptedEmailDelivery(
          familyId: '11111111-1111-4111-8111-111111111111',
          suggestionId: 'tampered',
          ciphertext: Uint8List(64),
          receivedAt: DateTime.now(),
          expiresAt: DateTime.now().add(const Duration(days: 1)),
        ),
      ],
      dismissRemote: (_) async {},
    );

    await inbox.refresh();

    expect(inbox.suggestions, isEmpty);
  });
}
