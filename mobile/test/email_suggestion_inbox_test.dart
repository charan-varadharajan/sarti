import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
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
          'version': 1,
          'suggestion_id': 'suggestion',
          'sender': 'teacher@example.com',
          'subject': 'Swimming Tuesday at 5 PM',
          'body': 'Please review this schedule.',
          'received_at': '2026-10-11T12:00:00Z',
        }),
      );
      final delivery = EncryptedEmailDelivery(
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
            'version': 1,
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
          suggestionId: 'expected',
          ciphertext: mismatched,
          receivedAt: DateTime.now(),
          expiresAt: DateTime.now().add(const Duration(days: 1)),
        ),
        EncryptedEmailDelivery(
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
