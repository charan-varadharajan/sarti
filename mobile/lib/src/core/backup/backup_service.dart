import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bip39_mnemonic/bip39_mnemonic.dart';
import 'package:crypto/crypto.dart';
import 'package:sodium/sodium.dart';

/// Thrown when a backup operation fails (wrong key, corruption, bad format).
class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => 'BackupException: $message';
}

/// Backup file format (ADR-025):
///
/// [4]  magic   0x53415254 ("SART")
/// [1]  version 0x01
/// [16] salt    (PBKDF2 input, random per backup)
/// [24] nonce   (XChaCha20-Poly1305, random per backup)
/// [N]  ciphertext + 16-byte Poly1305 tag (appended by libsodium)
///
/// Key derivation: PBKDF2-HMAC-SHA256(phrase, salt, 200000 iterations, 32 bytes).
/// Note: Argon2id is preferable but requires sodium_sumo which is not available
/// as a Flutter-compatible pinned package (documented limitation, ADR-025).
class BackupService {
  static const _pbkdf2Iterations = 200000;

  /// Generates a checksum-validated 12-word BIP-39 English recovery phrase.
  ///
  /// Entropy comes from the existing libsodium secure-random source. BIP-39
  /// encoding and checksum generation are delegated to the reviewed package
  /// selected by ADR-031.
  static String generateRecoveryPhrase({required Sodium sodium}) {
    return Mnemonic(sodium.randombytes.buf(16), Language.english).sentence;
  }

  /// Returns a canonical 12-word BIP-39 English phrase or throws
  /// [BackupException] before key derivation for invalid recovery input.
  static String validateRecoveryPhrase(String phrase) {
    final canonical = phrase.trim().split(RegExp(r'\s+')).join(' ');
    try {
      final mnemonic = Mnemonic.fromSentence(canonical, Language.english);
      if (mnemonic.words.length != 12) {
        throw const BackupException(
          'Recovery phrase must contain exactly 12 BIP-39 English words.',
        );
      }
      return mnemonic.sentence;
    } on BackupException {
      rethrow;
    } catch (_) {
      throw const BackupException(
        'Recovery phrase is not a valid 12-word BIP-39 English phrase.',
      );
    }
  }

  /// Derives a 32-byte backup key from [phrase] and [salt] using
  /// PBKDF2-HMAC-SHA256 with [_pbkdf2Iterations] iterations.
  /// [salt] must be 16 bytes.
  static Uint8List deriveKey(String phrase, {required Uint8List salt}) {
    if (salt.length != 16) {
      throw ArgumentError.value(salt.length, 'salt.length', 'must be 16');
    }
    final phraseBytes = utf8.encode(validateRecoveryPhrase(phrase));
    return _pbkdf2(phraseBytes, salt, _pbkdf2Iterations, 32);
  }

  /// Creates an encrypted backup of the SQLCipher database at [databasePath]
  /// and writes it to [outputPath] (ADR-025 format).
  /// [sodium] must be an already-initialised [Sodium] instance.
  static void createBackup({
    required String databasePath,
    required String outputPath,
    required String recoveryPhrase,
    required Sodium sodium,
  }) {
    final plaintext = File(databasePath).readAsBytesSync();
    final salt = Uint8List.fromList(sodium.randombytes.buf(16));
    final key = deriveKey(recoveryPhrase, salt: salt);
    final secureKey = SecureKey.fromList(sodium, key);
    try {
      final nonce = Uint8List.fromList(
        sodium.randombytes.buf(
          sodium.crypto.aeadXChaCha20Poly1305IETF.nonceBytes,
        ),
      );
      final ciphertext = sodium.crypto.aeadXChaCha20Poly1305IETF.encrypt(
        message: plaintext,
        nonce: nonce,
        key: secureKey,
      );
      final out = File(outputPath).openSync(mode: FileMode.writeOnly);
      try {
        out.writeFromSync([0x53, 0x41, 0x52, 0x54, 0x01]);
        out.writeFromSync(salt);
        out.writeFromSync(nonce);
        out.writeFromSync(ciphertext);
      } finally {
        out.closeSync();
      }
    } finally {
      secureKey.dispose();
    }
  }

  /// Decrypts a backup file at [backupPath] and writes the plaintext database
  /// to [outputPath]. Throws [BackupException] on any failure.
  /// [sodium] must be an already-initialised [Sodium] instance.
  static void restoreBackup({
    required String backupPath,
    required String outputPath,
    required String recoveryPhrase,
    required Sodium sodium,
  }) {
    final bytes = File(backupPath).readAsBytesSync();
    if (bytes.length < 61) {
      throw const BackupException('Backup file is too small or corrupted.');
    }
    if (bytes[0] != 0x53 ||
        bytes[1] != 0x41 ||
        bytes[2] != 0x52 ||
        bytes[3] != 0x54) {
      throw const BackupException('Not a valid Sarti backup file.');
    }
    if (bytes[4] != 0x01) {
      throw const BackupException('Unsupported backup version.');
    }
    final salt = Uint8List.fromList(bytes.sublist(5, 21));
    final nonce = Uint8List.fromList(bytes.sublist(21, 45));
    final ciphertext = Uint8List.fromList(bytes.sublist(45));
    final key = deriveKey(recoveryPhrase, salt: salt);
    final secureKey = SecureKey.fromList(sodium, key);
    try {
      final Uint8List plaintext;
      try {
        plaintext = sodium.crypto.aeadXChaCha20Poly1305IETF.decrypt(
          cipherText: ciphertext,
          nonce: nonce,
          key: secureKey,
        );
      } catch (_) {
        throw const BackupException(
          'Decryption failed. The recovery phrase may be incorrect or the '
          'backup file may be corrupted.',
        );
      }
      File(outputPath).writeAsBytesSync(plaintext);
    } finally {
      secureKey.dispose();
    }
  }

  // ── PBKDF2-HMAC-SHA256 ────────────────────────────────────────────────────

  static Uint8List _pbkdf2(
    List<int> password,
    List<int> salt,
    int iterations,
    int keyLength,
  ) {
    final hmac = Hmac(sha256, password);
    final blocks = (keyLength / 32).ceil();
    final result = <int>[];
    for (var block = 1; block <= blocks; block++) {
      final saltBlock = Uint8List(salt.length + 4);
      saltBlock.setAll(0, salt);
      saltBlock[salt.length] = (block >> 24) & 0xff;
      saltBlock[salt.length + 1] = (block >> 16) & 0xff;
      saltBlock[salt.length + 2] = (block >> 8) & 0xff;
      saltBlock[salt.length + 3] = block & 0xff;
      var u = hmac.convert(saltBlock).bytes;
      final xor = List<int>.from(u);
      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < xor.length; j++) {
          xor[j] ^= u[j];
        }
      }
      result.addAll(xor);
    }
    return Uint8List.fromList(result.sublist(0, keyLength));
  }
}
