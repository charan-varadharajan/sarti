import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sarti_mobile/src/core/backup/backup_service.dart';
import 'package:sarti_mobile/src/core/crypto/device_key_store.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sodium/sodium.dart';

/// Stages recovery without replacing an open database. A protected journal
/// makes activation retryable if the app exits between the file and key writes.
class BackupRecovery {
  static const _journal = 'backup-recovery-pending-v1';

  static Future<void> stage({
    required Uint8List blob,
    required String phrase,
    required String familyId,
    required SartiDatabase current,
    required Sodium sodium,
    required SecretStore secrets,
    String? adultId,
  }) async {
    if (current.raw.select('SELECT id FROM households').isNotEmpty) {
      throw const BackupException('Restore requires an empty local calendar.');
    }
    if (await secrets.read(_journal) != null) {
      throw const BackupException(
        'Restart Sarti to finish the pending restore.',
      );
    }
    final folder = Directory.systemTemp.createTempSync('sarti-recovery-');
    final pending = File('${current.path}.recovery');
    Uint8List? recoveredKey;
    try {
      final backup = File('${folder.path}/backup');
      backup.writeAsBytesSync(blob);
      final result = BackupService.restoreBackup(
        backupPath: backup.path,
        outputPath: pending.path,
        recoveryPhrase: phrase,
        sodium: sodium,
      );
      recoveredKey = result.databaseKey;
      final restored = SartiDatabase.open(pending.path, recoveredKey);
      try {
        final families = restored.raw.select('SELECT id FROM households');
        if (families.length != 1 || families.single['id'] != familyId) {
          throw const BackupException('Backup belongs to a different family.');
        }
        final scope = restored.raw.select(
          "SELECT value FROM app_preferences WHERE key='backup-scope-v1'",
        );
        if (adultId != null) {
          if (scope.isEmpty ||
              scope.single['value'] != 'adult:$adultId' ||
              restored.raw.select(
                'SELECT 1 FROM personal_calendars WHERE adult_id!=?',
                [adultId],
              ).isNotEmpty) {
            throw const BackupException(
              'Private backup belongs to a different adult.',
            );
          }
        } else if (restored.raw
            .select('SELECT 1 FROM personal_calendars')
            .isNotEmpty) {
          throw const BackupException(
            'Private content requires adult-specific recovery.',
          );
        }
        final integrity = restored.raw.select('PRAGMA integrity_check');
        if (integrity.single.values.single != 'ok' ||
            restored.raw.select('PRAGMA foreign_key_check').isNotEmpty) {
          throw const BackupException('Backup database is damaged.');
        }
        restored.transaction(() {
          for (final table in [
            'outbox',
            if (adultId == null) 'applied_operations',
            'sync_state',
            if (adultId == null) 'resource_keys',
            if (adultId == null) 'event_versions',
            'app_preferences',
          ]) {
            restored.raw.execute('DELETE FROM $table');
          }
          if (adultId == null) {
            restored.raw.execute(
              "INSERT INTO app_preferences VALUES ('retention-recovery-pending','true')",
            );
          }
          if (adultId != null) {
            restored.raw.execute('INSERT INTO app_preferences VALUES (?,?)', [
              'family-access-$familyId',
              jsonEncode({'role': 'guardian', 'permission': 'read'}),
            ]);
          }
        });
      } finally {
        restored.close();
      }
      await secrets.write(_journal, base64UrlEncode(recoveredKey));
    } catch (_) {
      if (pending.existsSync()) pending.deleteSync();
      rethrow;
    } finally {
      recoveredKey?.fillRange(0, recoveredKey.length, 0);
      folder.deleteSync(recursive: true);
    }
  }

  /// Run before opening the database, after platform user presence is verified.
  static Future<void> activate(String path, SecretStore secrets) async {
    final encoded = await secrets.read(_journal);
    if (encoded == null) return;
    final key = base64Url.decode(encoded);
    try {
      final pending = File('$path.recovery');
      final candidate = pending.existsSync() ? pending.path : path;
      final checked = SartiDatabase.open(candidate, key);
      checked.close();
      await secrets.write('database-key-v1', encoded);
      if (pending.existsSync()) pending.renameSync(path);
      await secrets.delete(_journal);
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  static Future<Uint8List> snapshot({
    required SartiDatabase database,
    required Uint8List key,
    required String phrase,
    required Sodium sodium,
    required String familyId,
    String? adultId,
  }) async {
    final rows = database.raw.select('SELECT id FROM households');
    if (rows.length != 1 || rows.single['id'] != familyId) {
      throw const BackupException('Backup must contain exactly one family.');
    }
    if (key.length != 32) {
      throw const BackupException('Invalid snapshot key size.');
    }
    final folder = Directory.systemTemp.createTempSync('sarti-snapshot-');
    final snapshotKey = sodium.randombytes.buf(32);
    final hex = snapshotKey
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    try {
      final snapshotPath = '${folder.path}/snapshot.db';
      database.raw.execute(
        'ATTACH DATABASE ? AS backup_snapshot KEY "x\'$hex\'"',
        [snapshotPath],
      );
      try {
        database.raw.select("SELECT sqlcipher_export('backup_snapshot')");
        database.raw.execute(
          'PRAGMA backup_snapshot.user_version = ${SartiDatabase.schemaVersion}',
        );
      } finally {
        database.raw.execute('DETACH DATABASE backup_snapshot');
      }
      final sanitized = SartiDatabase.open(snapshotPath, snapshotKey);
      try {
        sanitized.raw.execute('PRAGMA secure_delete=ON');
        sanitized.transaction(() {
          final excluded = sanitized.raw.select(
            'SELECT resource_id FROM personal_calendars WHERE (? IS NULL OR adult_id != ?)',
            [adultId, adultId],
          );
          for (final row in excluded) {
            final resource = row['resource_id'];
            sanitized.raw.execute(
              'DELETE FROM calendar_deletions WHERE resource_id=?',
              [resource],
            );
            sanitized.raw.execute(
              'DELETE FROM retention_conflicts WHERE resource_id=?',
              [resource],
            );
            sanitized.raw.execute('DELETE FROM conflicts WHERE resource_id=?', [
              resource,
            ]);
            sanitized.raw.execute('DELETE FROM outbox WHERE resource_id=?', [
              resource,
            ]);
            sanitized.raw.execute(
              'DELETE FROM resource_keys WHERE resource_id=?',
              [resource],
            );
            sanitized.raw.execute(
              'DELETE FROM resource_catalog WHERE resource_id=?',
              [resource],
            );
            sanitized.raw.execute(
              'DELETE FROM events WHERE calendar_resource_id=?',
              [resource],
            );
            sanitized.raw.execute(
              'DELETE FROM personal_calendars WHERE resource_id=?',
              [resource],
            );
          }
          // Private mappings and preferences never belong in family snapshots.
          if (adultId == null) {
            sanitized.raw.execute('DELETE FROM appointment_shares');
          }
          sanitized.raw.execute('DELETE FROM app_preferences');
          sanitized.raw.execute(
            "INSERT OR REPLACE INTO app_preferences(key,value) VALUES ('backup-scope-v1',?)",
            [adultId == null ? 'family' : 'adult:$adultId'],
          );
        });
        sanitized.raw.execute('VACUUM');
      } finally {
        sanitized.close();
      }
      final output = '${folder.path}/backup.srtbk';
      BackupService.createBackup(
        databasePath: snapshotPath,
        outputPath: output,
        recoveryPhrase: phrase,
        databaseKey: snapshotKey,
        sodium: sodium,
      );
      return File(output).readAsBytesSync();
    } finally {
      snapshotKey.fillRange(0, snapshotKey.length, 0);
      folder.deleteSync(recursive: true);
    }
  }
}
