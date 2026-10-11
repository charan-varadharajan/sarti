import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/core/backup/backup_service.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sodium/sodium.dart';

void main() {
  late Sodium sodium;
  setUpAll(() async => sodium = await SodiumInit.init());

  group('BackupService', () {
    late Directory tempDir;

    setUp(() => tempDir = Directory.systemTemp.createTempSync('sarti-backup-'));
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('generates a 12-word recovery phrase', () {
      final phrase = BackupService.generateRecoveryPhrase();
      final words = phrase.trim().split(RegExp(r'\s+'));
      expect(words, hasLength(12));
      for (final word in words) {
        expect(word, isNotEmpty);
        expect(word, matches(RegExp(r'^[a-z]+')));
      }
    });

    test('same phrase always derives the same key', () {
      const phrase =
          'abandon ability able about above absent absorb abstract absurd abuse access accident';
      final k1 = BackupService.deriveKey(phrase, salt: Uint8List(16));
      final k2 = BackupService.deriveKey(phrase, salt: Uint8List(16));
      expect(k1, equals(k2));
    });

    test('different phrases derive different keys', () {
      const p1 =
          'abandon ability able about above absent absorb abstract absurd abuse access accident';
      const p2 =
          'zoo zebra yellow xray wolf violet umbrella tiger snake rabbit queen parrot';
      final salt = Uint8List(16);
      expect(
        BackupService.deriveKey(p1, salt: salt),
        isNot(equals(BackupService.deriveKey(p2, salt: salt))),
      );
    });

    test('different salts derive different keys', () {
      const phrase =
          'abandon ability able about above absent absorb abstract absurd abuse access accident';
      final s1 = Uint8List(16);
      final s2 = Uint8List.fromList(List.filled(16, 1));
      expect(
        BackupService.deriveKey(phrase, salt: s1),
        isNot(equals(BackupService.deriveKey(phrase, salt: s2))),
      );
    });

    test('backup file has correct magic header', () {
      final dbPath = '${tempDir.path}/test.db';
      final db = SartiDatabase.open(dbPath, Uint8List(32));
      db.close();

      const phrase =
          'abandon ability able about above absent absorb abstract absurd abuse access accident';
      final backupPath = '${tempDir.path}/backup.srtbk';
      BackupService.createBackup(
        databasePath: dbPath,
        outputPath: backupPath,
        recoveryPhrase: phrase,
        sodium: sodium,
      );

      final bytes = File(backupPath).readAsBytesSync();
      expect(bytes[0], 0x53);
      expect(bytes[1], 0x41);
      expect(bytes[2], 0x52);
      expect(bytes[3], 0x54);
      expect(bytes[4], 0x01);
    });

    test('backup file minimum size: header + salt + nonce + tag', () {
      final dbPath = '${tempDir.path}/test.db';
      final db = SartiDatabase.open(dbPath, Uint8List(32));
      db.close();

      const phrase =
          'abandon ability able about above absent absorb abstract absurd abuse access accident';
      final backupPath = '${tempDir.path}/backup.srtbk';
      BackupService.createBackup(
        databasePath: dbPath,
        outputPath: backupPath,
        recoveryPhrase: phrase,
        sodium: sodium,
      );

      final size = File(backupPath).lengthSync();
      // 4 magic + 1 version + 16 salt + 24 nonce + 16 tag = 61 minimum
      expect(size, greaterThan(61));
    });

    test('restore succeeds with correct phrase', () {
      final dbPath = '${tempDir.path}/source.db';
      final db = SartiDatabase.open(dbPath, Uint8List(32));
      db.raw.execute(
        'INSERT INTO households(id, display_name, created_at, calendar_resource_id) VALUES (?, ?, ?, ?)',
        ['hh1', 'Test Family', '2026-01-01T00:00:00Z', 'cal1'],
      );
      db.close();

      const phrase =
          'abandon ability able about above absent absorb abstract absurd abuse access accident';
      final backupPath = '${tempDir.path}/backup.srtbk';
      BackupService.createBackup(
        databasePath: dbPath,
        outputPath: backupPath,
        recoveryPhrase: phrase,
        sodium: sodium,
      );

      final restorePath = '${tempDir.path}/restored.db';
      BackupService.restoreBackup(
        backupPath: backupPath,
        outputPath: restorePath,
        recoveryPhrase: phrase,
        sodium: sodium,
      );

      final restored = SartiDatabase.open(restorePath, Uint8List(32));
      final rows = restored.raw.select('SELECT display_name FROM households');
      restored.close();
      expect(rows.single['display_name'], 'Test Family');
    });

    test('restore fails with wrong phrase', () {
      final dbPath = '${tempDir.path}/source.db';
      final db = SartiDatabase.open(dbPath, Uint8List(32));
      db.close();

      const phrase =
          'abandon ability able about above absent absorb abstract absurd abuse access accident';
      const wrongPhrase =
          'zoo zebra yellow xray wolf violet umbrella tiger snake rabbit queen parrot';
      final backupPath = '${tempDir.path}/backup.srtbk';
      BackupService.createBackup(
        databasePath: dbPath,
        outputPath: backupPath,
        recoveryPhrase: phrase,
        sodium: sodium,
      );

      expect(
        () => BackupService.restoreBackup(
          backupPath: backupPath,
          outputPath: '${tempDir.path}/bad.db',
          recoveryPhrase: wrongPhrase,
          sodium: sodium,
        ),
        throwsA(isA<BackupException>()),
      );
    });

    test('restore fails with corrupted backup', () {
      final dbPath = '${tempDir.path}/source.db';
      final db = SartiDatabase.open(dbPath, Uint8List(32));
      db.close();

      const phrase =
          'abandon ability able about above absent absorb abstract absurd abuse access accident';
      final backupPath = '${tempDir.path}/backup.srtbk';
      BackupService.createBackup(
        databasePath: dbPath,
        outputPath: backupPath,
        recoveryPhrase: phrase,
        sodium: sodium,
      );

      final bytes = File(backupPath).readAsBytesSync();
      bytes[bytes.length - 20] ^= 0xFF;
      File(backupPath).writeAsBytesSync(bytes);

      expect(
        () => BackupService.restoreBackup(
          backupPath: backupPath,
          outputPath: '${tempDir.path}/bad.db',
          recoveryPhrase: phrase,
          sodium: sodium,
        ),
        throwsA(isA<BackupException>()),
      );
    });

    test('restore fails with truncated backup', () {
      final backupPath = '${tempDir.path}/truncated.srtbk';
      File(backupPath).writeAsBytesSync([0x53, 0x41, 0x52, 0x54, 0x01]);

      expect(
        () => BackupService.restoreBackup(
          backupPath: backupPath,
          outputPath: '${tempDir.path}/bad.db',
          recoveryPhrase: 'any phrase here',
          sodium: sodium,
        ),
        throwsA(isA<BackupException>()),
      );
    });

    test('backup key is independent from SQLCipher database key', () {
      const phrase =
          'abandon ability able about above absent absorb abstract absurd abuse access accident';
      final salt = Uint8List(16);
      final backupKey = BackupService.deriveKey(phrase, salt: salt);
      final dbKey = Uint8List(32);
      expect(backupKey, isNot(equals(dbKey)));
    });
  });
}
