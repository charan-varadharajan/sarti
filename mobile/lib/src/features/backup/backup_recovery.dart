import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sarti_mobile/src/core/backup/backup_service.dart';
import 'package:sarti_mobile/src/core/crypto/device_key_store.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sodium/sodium.dart';

import '../calendar/data/calendar_repository.dart';
import '../../core/ids.dart';

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
        _prepareRestored(restored, familyId, adultId);
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

  static void _prepareRestored(
    SartiDatabase restored,
    String familyId,
    String? adultId,
  ) {
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
      if (adultId == null) {
        CalendarRepository(
          restored,
          deviceId: newId(),
        ).initializeFamilyRecovery();
      }
      for (final table in [
        'outbox',
        'sync_state',
        'device_sync_state',
        'app_preferences',
        if (adultId != null) 'recovery_intents',
        if (adultId != null) 'recovery_state',
      ]) {
        restored.raw.execute('DELETE FROM $table');
      }
      if (adultId == null) {
        restored.raw.execute(
          "INSERT INTO app_preferences VALUES ('retention-recovery-pending','true')",
        );
      }
      if (adultId == null) {
        final row = restored.raw
            .select('SELECT profile_vector_json FROM recovery_state')
            .single;
        if (recoveryVector(row['profile_vector_json']) != null) {
          restored.raw.execute('INSERT INTO app_preferences VALUES (?,?)', [
            'household-vector-$familyId',
            row['profile_vector_json'],
          ]);
        }
      }
      {
        restored.raw.execute('INSERT INTO app_preferences VALUES (?,?)', [
          'family-access-$familyId',
          jsonEncode({'role': 'guardian', 'permission': 'read'}),
        ]);
      }
    });
  }

  /// Import a missing family in one live SQLCipher transaction. The current
  /// database/key/device identity stays; in-flight writes to other families can
  /// finish against the same store, so no file activation can lose late work.
  static Future<void> importHousehold({
    required Uint8List blob,
    required String phrase,
    required String familyId,
    required SartiDatabase current,
    required Sodium sodium,
  }) async {
    if (current.raw.select('SELECT 1 FROM households WHERE id=?', [
      familyId,
    ]).isNotEmpty) {
      throw const BackupException('This household is already on this phone.');
    }
    final folder = Directory.systemTemp.createTempSync('sarti-scoped-import-');
    Uint8List? recoveredKey;
    try {
      final backup = File('${folder.path}/snapshot.srtbk')
        ..writeAsBytesSync(blob);
      final path = '${folder.path}/restored.db';
      final result = BackupService.restoreBackup(
        backupPath: backup.path,
        outputPath: path,
        recoveryPhrase: phrase,
        sodium: sodium,
      );
      recoveredKey = result.databaseKey;
      final restored = SartiDatabase.open(path, recoveredKey);
      try {
        _prepareRestored(restored, familyId, null);
        Set<String> resourceIds(SartiDatabase db) => db.raw
            .select(
              'SELECT calendar_resource_id AS id FROM households UNION SELECT id FROM children UNION SELECT id FROM participant_profiles UNION SELECT resource_id AS id FROM resource_catalog UNION SELECT resource_id AS id FROM personal_calendars UNION SELECT resource_id AS id FROM resource_keys',
            )
            .map((r) => r['id'] as String)
            .toSet();
        final incoming = resourceIds(restored);
        if (incoming.intersection(resourceIds(current)).isNotEmpty) {
          throw const BackupException(
            'Snapshot resource identities conflict with this phone.',
          );
        }
        for (final row in restored.raw.select('SELECT * FROM conflicts')) {
          if (!incoming.contains(row['resource_id'])) {
            throw const BackupException('Snapshot conflict scope is invalid.');
          }
          for (final column in ['local_payload_json', 'remote_payload_json']) {
            final payload = jsonDecode(row[column] as String) as Map;
            if (payload['householdId'] != familyId ||
                payload['calendarResourceId'] != row['resource_id']) {
              throw const BackupException(
                'Snapshot conflict content is outside this household.',
              );
            }
          }
        }
        current.transaction(() {
          // Fixed table order respects all foreign keys. Columns are taken from
          // the trusted current schema; untrusted snapshot SQL is never executed
          // against the live store. Plain INSERT rejects every identity collision.
          for (final table in [
            'households',
            'guardians',
            'children',
            'participant_profiles',
            'personal_calendars',
            'events',
            'event_children',
            'event_participants',
            'reminders',
            'event_versions',
            'child_sync',
            'child_profile_versions',
            'appointment_shares',
            'resource_catalog',
            'resource_keys',
            'calendar_deletions',
            'retention_conflicts',
            'conflicts',
            'recovery_state',
            'recovery_intents',
          ]) {
            final columns = current.raw
                .select('PRAGMA table_info($table)')
                .map((r) => r['name'] as String)
                .toList();
            final names = columns.map((c) => '"$c"').join(',');
            final placeholders = List.filled(columns.length, '?').join(',');
            for (final row in restored.raw.select(
              'SELECT $names FROM $table',
            )) {
              current.raw.execute(
                'INSERT INTO $table ($names) VALUES ($placeholders)',
                [for (final name in columns) row[name]],
              );
            }
          }
          for (final key in [
            'household-vector-$familyId',
            'family-access-$familyId',
          ]) {
            final rows = restored.raw.select(
              'SELECT value FROM app_preferences WHERE key=?',
              [key],
            );
            if (rows.isNotEmpty) {
              current.raw.execute('INSERT INTO app_preferences VALUES (?,?)', [
                key,
                rows.single['value'],
              ]);
            }
          }
          if (current.raw.select('PRAGMA foreign_key_check').isNotEmpty) {
            throw const BackupException('Snapshot relationships are invalid.');
          }
        });
      } finally {
        restored.close();
      }
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
    if (!rows.any((row) => row['id'] == familyId)) {
      throw const BackupException('Unknown backup household.');
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
          // Work on the encrypted snapshot, never on the live database. Every
          // retained content/key row must be attributable to the requested scope.
          final allowed = <String>{
            for (final row in sanitized.raw.select(
              'SELECT calendar_resource_id FROM households WHERE id=?',
              [familyId],
            ))
              row['calendar_resource_id'] as String,
            for (final row in sanitized.raw.select(
              'SELECT id FROM children WHERE household_id=? UNION SELECT id FROM participant_profiles WHERE household_id=? UNION SELECT resource_id AS id FROM personal_calendars WHERE household_id=? UNION SELECT resource_id AS id FROM resource_catalog WHERE family_id=?',
              [familyId, familyId, familyId, familyId],
            ))
              row['id'] as String,
          };
          for (final table in [
            'resource_keys',
            'resource_catalog',
            'conflicts',
            'retention_conflicts',
          ]) {
            for (final row in sanitized.raw.select(
              'SELECT DISTINCT resource_id FROM $table',
            )) {
              if (!allowed.contains(row['resource_id'])) {
                sanitized.raw.execute(
                  'DELETE FROM $table WHERE resource_id=?',
                  [row['resource_id']],
                );
              }
            }
          }
          sanitized.raw.execute('DELETE FROM outbox WHERE family_id!=?', [
            familyId,
          ]);
          sanitized.raw.execute('DELETE FROM sync_state WHERE family_id!=?', [
            familyId,
          ]);
          sanitized.raw.execute('DELETE FROM device_sync_state');
          // Device-wide receipts cannot be exported as if scoped. Event/profile
          // vectors and quarantined intent retain causal recovery information.
          sanitized.raw.execute(
            'DELETE FROM applied_operations WHERE operation_id NOT IN (SELECT operation_id FROM outbox)',
          );
          sanitized.raw.execute('DELETE FROM households WHERE id!=?', [
            familyId,
          ]);
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
            sanitized.raw.execute(
              'DELETE FROM recovery_intents WHERE resource_id=?',
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
          if (adultId == null) {
            final profile = sanitized.raw.select(
              'SELECT value FROM app_preferences WHERE key=?',
              ['household-vector-$familyId'],
            );
            final prior = sanitized.raw.select('SELECT * FROM recovery_state');
            final vector = profile.isEmpty
                ? (prior.isEmpty ? null : prior.single['profile_vector_json'])
                : profile.single['value'];
            final blocked =
                prior.isNotEmpty && prior.single['phase'] == 'blocked';
            sanitized.raw.execute(
              'INSERT OR REPLACE INTO recovery_state VALUES (?,?,?,?,?)',
              [
                familyId,
                blocked ? 'blocked' : 'snapshot',
                DateTime.now().toUtc().toIso8601String(),
                vector,
                blocked ? prior.single['reason'] : null,
              ],
            );
          } else {
            sanitized.raw.execute('DELETE FROM recovery_intents');
            sanitized.raw.execute('DELETE FROM recovery_state');
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
