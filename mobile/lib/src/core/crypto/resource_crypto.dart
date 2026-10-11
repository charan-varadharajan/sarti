import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium.dart';

class EncryptedResourcePayload {
  const EncryptedResourcePayload({
    required this.nonce,
    required this.ciphertext,
    required this.additionalData,
  });

  final Uint8List nonce;
  final Uint8List ciphertext;
  final Uint8List additionalData;
}

class ResourceCrypto {
  ResourceCrypto(this.sodium);

  final Sodium sodium;

  SecureKey newResourceKey() => sodium.crypto.aeadXChaCha20Poly1305IETF.keygen();

  EncryptedResourcePayload encrypt({
    required Uint8List plaintext,
    required SecureKey key,
    required Map<String, Object> metadata,
  }) {
    final aead = sodium.crypto.aeadXChaCha20Poly1305IETF;
    final nonce = sodium.randombytes.buf(aead.nonceBytes);
    final additionalData = Uint8List.fromList(utf8.encode(jsonEncode(metadata)));
    final ciphertext = aead.encrypt(
      message: plaintext,
      nonce: nonce,
      key: key,
      additionalData: additionalData,
    );
    return EncryptedResourcePayload(
      nonce: nonce,
      ciphertext: ciphertext,
      additionalData: additionalData,
    );
  }

  Uint8List decrypt(EncryptedResourcePayload payload, SecureKey key) => sodium
      .crypto
      .aeadXChaCha20Poly1305IETF
      .decrypt(
        cipherText: payload.ciphertext,
        nonce: payload.nonce,
        key: key,
        additionalData: payload.additionalData,
      );
}
