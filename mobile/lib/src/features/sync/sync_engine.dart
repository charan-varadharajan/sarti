import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sarti_mobile/src/core/crypto/resource_crypto.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/features/calendar/domain/calendar_event.dart';
import 'package:sodium/sodium.dart';

class RelayEnvelope {
  const RelayEnvelope({
    this.protocolVersion = 1,
    required this.serverSequence,
    required this.operationId,
    required this.familyId,
    required this.resourceId,
    required this.authorDeviceId,
    required this.deviceSequence,
    required this.keyEpoch,
    required this.logicalVersion,
    required this.nonce,
    required this.ciphertext,
    required this.contentDigest,
  });

  final int protocolVersion;
  final int serverSequence;
  final String operationId;
  final String familyId;
  final String resourceId;
  final String authorDeviceId;
  final int deviceSequence;
  final int keyEpoch;
  final Map<String, int> logicalVersion;
  final Uint8List nonce;
  final Uint8List ciphertext;
  final Uint8List contentDigest;
}

class RelayPage {
  const RelayPage(this.operations, this.nextCursor);

  final List<RelayEnvelope> operations;
  final int nextCursor;
}

abstract interface class EncryptedRelay {
  Future<void> upload(RelayEnvelope envelope);
  Future<RelayPage> download(String familyId, int cursor);
}

class SequenceReceipt {
  const SequenceReceipt({
    required this.operationId,
    required this.deviceId,
    required this.lastDeviceSequence,
    required this.receipt,
  });
  final String operationId, deviceId, receipt;
  final int lastDeviceSequence;
}

abstract interface class SequenceReviewRelay {
  Future<SequenceReceipt> reviewSequence(RelayEnvelope original);
}

/// The relay rejected a conflicting/stale envelope; no content was accepted.
class RelayConflict implements Exception {}

class SyncReport {
  const SyncReport({
    required this.uploaded,
    required this.applied,
    required this.conflicts,
  });

  final int uploaded;
  final int applied;
  final int conflicts;
}

String pendingOperationFingerprint(SartiDatabase database, String familyId) =>
    jsonEncode(
      database.raw
          .select(
            "SELECT * FROM outbox WHERE family_id=? AND state='pending' ORDER BY operation_id",
            [familyId],
          )
          .map((r) => Map<String, Object?>.from(r))
          .toList(),
    );

class SyncEngine {
  SyncEngine({
    required this.database,
    required this.repository,
    required this.crypto,
    required this.sodium,
    required this.relay,
    required this.deviceId,
  });

  final SartiDatabase database;
  final CalendarRepository repository;
  final ResourceCrypto crypto;
  final Sodium sodium;
  final EncryptedRelay relay;
  final String deviceId;

  static final _queues = Expando<Completer<void>>();

  Future<SyncReport> synchronize(
    String familyId, {
    bool downloadOnly = false,
  }) => _serialized(() => _synchronize(familyId, downloadOnly: downloadOnly));

  Future<T> _serialized<T>(Future<T> Function() action) async {
    while (true) {
      final previous = _queues[database];
      if (previous == null) break;
      await previous.future;
    }
    final gate = Completer<void>();
    _queues[database] = gate;
    try {
      return await action();
    } finally {
      // Release before delivering success/error to the caller. No failed future
      // or callback tied to a former widget-test zone remains in the scheduler.
      _queues[database] = null;
      gate.complete();
    }
  }

  String pendingFingerprint(String familyId) =>
      pendingOperationFingerprint(database, familyId);

  /// Explicit review preserves original bytes as quarantined encrypted local
  /// intent. No abandoned payload is renumbered or silently republished.
  Future<int> quarantineUnavailableFamily(
    String familyId, {
    required String reviewedFingerprint,
  }) => _serialized(() async {
    if (relay is! SequenceReviewRelay ||
        pendingFingerprint(familyId) != reviewedFingerprint) {
      throw StateError('Review the current pending changes.');
    }
    final rows = database.raw.select(
      "SELECT * FROM outbox WHERE family_id=? AND state='pending' ORDER BY operation_id",
      [familyId],
    );
    final uncertain = rows.where((r) => r['envelope_json'] != null).toList();
    if (uncertain.length != 1) {
      throw StateError('One exact uncertain upload is required.');
    }
    final original = _restoreEnvelope(
      uncertain.single['envelope_json'] as String,
    );
    if (original.authorDeviceId != deviceId || original.familyId != familyId) {
      throw StateError('The original upload belongs to a different device.');
    }
    final receipt = await (relay as SequenceReviewRelay).reviewSequence(
      original,
    );
    if (receipt.operationId != original.operationId ||
        receipt.deviceId != deviceId ||
        receipt.lastDeviceSequence < 0 ||
        receipt.lastDeviceSequence >= 9223372036854775807 ||
        !{'accepted', 'not_accepted', 'unknown'}.contains(receipt.receipt) ||
        (receipt.receipt == 'accepted' &&
            receipt.lastDeviceSequence < original.deviceSequence) ||
        (receipt.receipt == 'not_accepted' &&
            receipt.lastDeviceSequence >= original.deviceSequence) ||
        (receipt.receipt == 'unknown' &&
            receipt.lastDeviceSequence < original.deviceSequence) ||
        pendingFingerprint(familyId) != reviewedFingerprint) {
      throw StateError('The receipt or reviewed changes do not match.');
    }
    final counter = database.raw.select(
      'SELECT next_device_sequence FROM device_sync_state WHERE device_id=?',
      [deviceId],
    );
    if (counter.isEmpty ||
        receipt.lastDeviceSequence + 1 <
            (counter.single['next_device_sequence'] as int)) {
      throw StateError('The server sequence moved backwards.');
    }
    database.transaction(() {
      for (final row in rows) {
        // A preexisting recovery intent is preserved rather than overwritten.
        if (database.raw.select(
          'SELECT 1 FROM recovery_intents WHERE source_operation_id=? OR queued_operation_id=?',
          [row['operation_id'], row['operation_id']],
        ).isNotEmpty) {
          throw StateError('Finish the existing scoped recovery review first.');
        }
        database.raw.execute(
          "INSERT INTO recovery_intents(source_operation_id,family_id,resource_id,kind,payload_json,vector_json,status,reason,original_envelope_json,server_receipt) VALUES (?,?,?,?,?,?,'quarantined','lost_write_authority',?,?)",
          [
            row['operation_id'],
            familyId,
            row['resource_id'],
            row['kind'],
            row['payload_json'],
            row['vector_json'],
            row['envelope_json'],
            row['envelope_json'] == null ? 'not_accepted' : receipt.receipt,
          ],
        );
        database.raw.execute('DELETE FROM outbox WHERE operation_id=?', [
          row['operation_id'],
        ]);
      }
      database.raw.execute(
        'UPDATE device_sync_state SET next_device_sequence=? WHERE device_id=?',
        [receipt.lastDeviceSequence + 1, deviceId],
      );
      database.raw.execute(
        'UPDATE sync_state SET next_device_sequence=? WHERE family_id=?',
        [receipt.lastDeviceSequence + 1, familyId],
      );
    });
    return rows.length;
  });

  Future<SyncReport> _synchronize(
    String familyId, {
    required bool downloadOnly,
  }) async {
    final repository = this.repository.forHousehold(familyId);
    database.raw.execute(
      'INSERT OR IGNORE INTO device_sync_state SELECT ?,COALESCE(MAX(next_device_sequence),1) FROM sync_state',
      [deviceId],
    );
    database.raw.execute(
      'INSERT OR IGNORE INTO sync_state(family_id) VALUES (?)',
      [familyId],
    );
    var uploaded = 0;
    while (!downloadOnly) {
      final rows = database.raw.select(
        "SELECT * FROM outbox WHERE family_id = ? AND state = 'pending' ORDER BY created_at, operation_id LIMIT 1",
        [familyId],
      );
      if (rows.isEmpty) break;
      final row = rows.first;
      if (repository.recoveryPending &&
          (repository.recoveryState?['phase'] != 'review' ||
              database.raw.select(
                "SELECT 1 FROM recovery_intents WHERE queued_operation_id=? AND status='queued' AND COALESCE(reviewed_payload_json,payload_json)=? AND COALESCE(reviewed_vector_json,vector_json)=? AND family_id=? AND resource_id=? AND (kind=? OR (kind='child_created' AND ?='child_updated'))",
                [
                  row['operation_id'],
                  row['payload_json'],
                  row['vector_json'],
                  row['family_id'],
                  row['resource_id'],
                  row['kind'],
                  row['kind'],
                ],
              ).isEmpty)) {
        throw StateError('Recovered outgoing work needs explicit review.');
      }
      // A timed-out upload may have been accepted. Retry its original bytes
      // before another context can consume this device's next sequence.
      if (database.raw.select(
        "SELECT 1 FROM outbox WHERE state='pending' AND envelope_json IS NOT NULL AND family_id!=?",
        [familyId],
      ).isNotEmpty) {
        throw StateError(
          'Retry the pending household before uploading another.',
        );
      }
      final sequence =
          database.raw.select(
                'SELECT next_device_sequence FROM device_sync_state WHERE device_id=?',
                [deviceId],
              ).single['next_device_sequence']
              as int;
      late final RelayEnvelope envelope;
      if (row['envelope_json'] != null) {
        envelope = _restoreEnvelope(row['envelope_json'] as String);
        if (envelope.authorDeviceId != deviceId ||
            envelope.deviceSequence != sequence) {
          throw StateError(
            'Pending operation belongs to a different device session.',
          );
        }
      } else {
        final keyEpoch = _latestKeyEpoch(row['resource_id'] as String);
        final metadata = <String, Object>{
          'protocol': 2,
          'familyId': familyId,
          'resourceId': row['resource_id'] as String,
          'keyEpoch': keyEpoch,
          'operationId': row['operation_id'] as String,
          'authorDeviceId': deviceId,
          'deviceSequence': sequence,
          'logicalVersion': Map<String, int>.from(
            jsonDecode(row['vector_json'] as String) as Map,
          ),
        };
        final key = _key(row['resource_id'] as String, keyEpoch);
        try {
          final encrypted = crypto.encrypt(
            plaintext: Uint8List.fromList(
              utf8.encode(
                jsonEncode({
                  'kind': row['kind'] as String,
                  'payload': jsonDecode(row['payload_json'] as String),
                }),
              ),
            ),
            key: key,
            metadata: metadata,
          );
          envelope = RelayEnvelope(
            protocolVersion: 2,
            serverSequence: 0,
            operationId: row['operation_id'] as String,
            familyId: familyId,
            resourceId: row['resource_id'] as String,
            authorDeviceId: deviceId,
            deviceSequence: sequence,
            keyEpoch: keyEpoch,
            logicalVersion: Map<String, int>.from(
              metadata['logicalVersion']! as Map,
            ),
            nonce: encrypted.nonce,
            ciphertext: encrypted.ciphertext,
            contentDigest: Uint8List.fromList(
              sha256.convert([
                ...encrypted.nonce,
                ...encrypted.ciphertext,
              ]).bytes,
            ),
          );
          database.raw.execute(
            'UPDATE outbox SET envelope_json = ? WHERE operation_id = ?',
            [_storeEnvelope(envelope), envelope.operationId],
          );
        } finally {
          key.dispose();
        }
      }
      try {
        await relay.upload(envelope);
      } on RelayConflict {
        if (envelope.keyEpoch >= _latestKeyEpoch(envelope.resourceId)) rethrow;
        // An exact old-epoch retry is acknowledged if already accepted. A
        // rejected stale envelope was not accepted: keep its operation ID and
        // sequence, then authenticate the same local payload with the new key.
        database.raw.execute(
          'UPDATE outbox SET envelope_json = NULL WHERE operation_id = ?',
          [envelope.operationId],
        );
        continue;
      }
      database.transaction(() {
        database.raw.execute(
          "UPDATE outbox SET state = 'uploaded' WHERE operation_id = ?",
          [row['operation_id']],
        );
        database.raw.execute(
          'UPDATE device_sync_state SET next_device_sequence=? WHERE device_id=?',
          [sequence + 1, deviceId],
        );
        // Retain legacy migration evidence; this is no longer authoritative.
        database.raw.execute(
          'UPDATE sync_state SET next_device_sequence = ? WHERE family_id = ?',
          [sequence + 1, familyId],
        );
      });
      uploaded++;
    }

    final state = database.raw.select(
      'SELECT server_cursor FROM sync_state WHERE family_id = ?',
      [familyId],
    ).first;
    final page = await relay.download(familyId, state['server_cursor'] as int);
    var applied = 0;
    var conflicts = 0;
    for (final envelope in page.operations) {
      if (envelope.familyId != familyId) {
        throw StateError('Invalid relay family scope.');
      }
      if (envelope.authorDeviceId == deviceId) continue;
      _verifyDigest(envelope);
      final metadata = <String, Object>{
        'protocol': envelope.protocolVersion,
        'familyId': envelope.familyId,
        'resourceId': envelope.resourceId,
        'keyEpoch': envelope.keyEpoch,
        'operationId': envelope.operationId,
        'authorDeviceId': envelope.authorDeviceId,
        'deviceSequence': envelope.deviceSequence,
        'logicalVersion': envelope.logicalVersion,
      };
      final key = _key(envelope.resourceId, envelope.keyEpoch);
      try {
        final plaintext = crypto.decrypt(
          EncryptedResourcePayload(
            nonce: envelope.nonce,
            ciphertext: envelope.ciphertext,
            additionalData: resourceAdditionalData(metadata),
          ),
          key,
        );
        final decoded = Map<String, Object?>.from(
          jsonDecode(utf8.decode(plaintext)) as Map,
        );
        if (decoded['kind'] == 'retention_deleted') {
          final result = repository.applyRetentionDeletion(
            operationId: envelope.operationId,
            familyId: familyId,
            resourceId: envelope.resourceId,
            vector: envelope.logicalVersion,
            payload: Map<String, Object?>.from(decoded['payload']! as Map),
          );
          if (result == RemoteApplyResult.applied) applied++;
          if (result == RemoteApplyResult.conflict) conflicts++;
          continue;
        }
        if (decoded['kind'] == 'household_shared') {
          final result = repository.applySharedHousehold(
            operationId: envelope.operationId,
            familyId: familyId,
            resourceId: envelope.resourceId,
            vector: envelope.logicalVersion,
            payload: Map<String, Object?>.from(decoded['payload']! as Map),
          );
          if (result == RemoteApplyResult.applied) applied++;
          continue;
        }
        if (decoded['kind'] == 'participant_upserted') {
          if (database.raw.select(
            "SELECT 1 FROM resource_catalog WHERE resource_id=? AND family_id=? AND kind='participant_profile'",
            [envelope.resourceId, familyId],
          ).isEmpty) {
            throw StateError('Invalid participant resource.');
          }
          final result = repository.applyParticipant(
            operationId: envelope.operationId,
            familyId: familyId,
            resourceId: envelope.resourceId,
            vector: envelope.logicalVersion,
            payload: Map<String, Object?>.from(decoded['payload']! as Map),
          );
          if (result == RemoteApplyResult.applied) applied++;
          continue;
        }
        if (decoded['kind'] == 'child_created' ||
            decoded['kind'] == 'child_updated') {
          final resource = database.raw.select(
            "SELECT 1 FROM resource_catalog WHERE resource_id = ? AND family_id = ? AND kind = 'child_profile'",
            [envelope.resourceId, familyId],
          );
          if (resource.isEmpty) {
            throw StateError('Invalid child resource kind.');
          }
          final result = repository.applyRemoteChild(
            operationId: envelope.operationId,
            familyId: familyId,
            resourceId: envelope.resourceId,
            keyEpoch: envelope.keyEpoch,
            vector: envelope.logicalVersion,
            allowUpdate: decoded['kind'] == 'child_updated',
            payload: Map<String, Object?>.from(decoded['payload']! as Map),
          );
          if (result == RemoteApplyResult.applied) applied++;
          continue;
        }
        final calendar = repository.load();
        if (calendar == null ||
            calendar.householdId != familyId ||
            (calendar.calendarResourceId != envelope.resourceId &&
                repository.personalResourceId != envelope.resourceId)) {
          throw StateError('Invalid calendar resource scope.');
        }
        if (decoded['kind'] == 'family_created') {
          if ((decoded['payload']! as Map)['householdId'] != familyId) {
            throw StateError('Invalid family payload scope.');
          }
          continue;
        }
        if (!{
          'event_upserted',
          'event_deleted',
          'conflict_resolved',
          'retention_kept',
        }.contains(decoded['kind'])) {
          throw StateError('Unknown sync operation kind.');
        }
        final event = CalendarEvent.fromJson(
          Map<String, Object?>.from(decoded['payload']! as Map),
        );
        if (event.householdId != familyId ||
            event.calendarResourceId != envelope.resourceId) {
          throw StateError('Invalid event payload scope.');
        }
        final result = repository.applyRemote(
          operationId: envelope.operationId,
          event: event,
          vector: envelope.logicalVersion,
        );
        if (result == RemoteApplyResult.applied) {
          applied++;
          if (decoded['kind'] == 'retention_kept') {
            database.raw.execute(
              'UPDATE event_versions SET retention_keep_vector=? WHERE event_id=?',
              [jsonEncode(envelope.logicalVersion), event.id],
            );
          }
        }
        if (result == RemoteApplyResult.conflict) conflicts++;
      } finally {
        key.dispose();
      }
    }
    database.raw.execute(
      'UPDATE sync_state SET server_cursor = ? WHERE family_id = ?',
      [page.nextCursor, familyId],
    );
    return SyncReport(
      uploaded: uploaded,
      applied: applied,
      conflicts: conflicts,
    );
  }

  String _storeEnvelope(RelayEnvelope e) => jsonEncode({
    'protocolVersion': e.protocolVersion,
    'operationId': e.operationId,
    'familyId': e.familyId,
    'resourceId': e.resourceId,
    'authorDeviceId': e.authorDeviceId,
    'deviceSequence': e.deviceSequence,
    'keyEpoch': e.keyEpoch,
    'logicalVersion': e.logicalVersion,
    'nonce': base64UrlEncode(e.nonce),
    'ciphertext': base64UrlEncode(e.ciphertext),
    'contentDigest': base64UrlEncode(e.contentDigest),
  });

  RelayEnvelope _restoreEnvelope(String value) {
    final e = jsonDecode(value) as Map<String, dynamic>;
    return RelayEnvelope(
      protocolVersion: e['protocolVersion'] as int? ?? 1,
      serverSequence: 0,
      operationId: e['operationId'] as String,
      familyId: e['familyId'] as String,
      resourceId: e['resourceId'] as String,
      authorDeviceId: e['authorDeviceId'] as String,
      deviceSequence: e['deviceSequence'] as int,
      keyEpoch: e['keyEpoch'] as int,
      logicalVersion: Map<String, int>.from(e['logicalVersion'] as Map),
      nonce: base64Url.decode(e['nonce'] as String),
      ciphertext: base64Url.decode(e['ciphertext'] as String),
      contentDigest: base64Url.decode(e['contentDigest'] as String),
    );
  }

  int _latestKeyEpoch(String resourceId) {
    final rows = database.raw.select(
      'SELECT max(key_epoch) AS epoch FROM resource_keys WHERE resource_id = ?',
      [resourceId],
    );
    final epoch = rows.first['epoch'] as int?;
    if (epoch == null) throw StateError('No resource key is available.');
    final catalog = database.raw.select(
      'SELECT key_epoch FROM resource_catalog WHERE resource_id = ?',
      [resourceId],
    );
    if (catalog.isNotEmpty && catalog.single['key_epoch'] != epoch) {
      throw StateError('The current resource key is unavailable.');
    }
    return epoch;
  }

  SecureKey _key(String resourceId, int epoch) {
    final bytes = database.resourceKey(resourceId, epoch);
    if (bytes == null) {
      throw StateError('The resource key epoch is unavailable.');
    }
    return SecureKey.fromList(sodium, bytes);
  }

  void _verifyDigest(RelayEnvelope envelope) {
    final expected = sha256.convert([
      ...envelope.nonce,
      ...envelope.ciphertext,
    ]).bytes;
    if (!_constantTimeEqual(expected, envelope.contentDigest)) {
      throw StateError('The encrypted operation digest is invalid.');
    }
  }

  bool _constantTimeEqual(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }
}
