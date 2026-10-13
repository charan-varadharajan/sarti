import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium.dart';

/// ADR-034: fixed field order and sorted vector keys for protocol 2.
/// Legacy encoding is intentionally unchanged; never try it after a v2 failure.
Uint8List resourceAdditionalData(Map<String, Object> metadata) {
  final protocol = metadata['protocol'] ?? 1;
  if (protocol == 1) {
    return Uint8List.fromList(utf8.encode(jsonEncode(metadata)));
  }
  if (protocol != 2) throw StateError('Unsupported sync protocol.');
  const fields = [
    'protocol',
    'familyId',
    'resourceId',
    'keyEpoch',
    'operationId',
    'authorDeviceId',
    'deviceSequence',
    'logicalVersion',
  ];
  if (metadata.length != fields.length || !fields.every(metadata.containsKey)) {
    throw StateError('Invalid authenticated metadata.');
  }
  final vector = Map<String, int>.from(metadata['logicalVersion']! as Map);
  final keys = vector.keys.toList()..sort();
  final canonical = <String, Object>{
    for (final field in fields)
      field: field == 'logicalVersion'
          ? {for (final key in keys) key: vector[key]!}
          : metadata[field]!,
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(canonical)));
}

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

  SecureKey newResourceKey() =>
      sodium.crypto.aeadXChaCha20Poly1305IETF.keygen();

  EncryptedResourcePayload encrypt({
    required Uint8List plaintext,
    required SecureKey key,
    required Map<String, Object> metadata,
  }) {
    final aead = sodium.crypto.aeadXChaCha20Poly1305IETF;
    final nonce = sodium.randombytes.buf(aead.nonceBytes);
    final additionalData = resourceAdditionalData(metadata);
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

  Uint8List decrypt(EncryptedResourcePayload payload, SecureKey key) =>
      sodium.crypto.aeadXChaCha20Poly1305IETF.decrypt(
        cipherText: payload.ciphertext,
        nonce: payload.nonce,
        key: key,
        additionalData: payload.additionalData,
      );
}
