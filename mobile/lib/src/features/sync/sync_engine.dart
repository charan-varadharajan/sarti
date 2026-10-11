import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sarti_mobile/src/core/crypto/resource_crypto.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/features/calendar/domain/calendar_event.dart';
import 'package:sodium/sodium.dart';

class RelayEnvelope {
  const RelayEnvelope({
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

  Future<SyncReport> synchronize(String familyId) async {
    database.raw.execute(
      'INSERT OR IGNORE INTO sync_state(family_id) VALUES (?)',
      [familyId],
    );
    var uploaded = 0;
    while (true) {
      final rows = database.raw.select(
        "SELECT * FROM outbox WHERE family_id = ? AND state = 'pending' ORDER BY created_at, operation_id LIMIT 1",
        [familyId],
      );
      if (rows.isEmpty) break;
      final row = rows.first;
      final sequence =
          database.raw.select(
                'SELECT next_device_sequence FROM sync_state WHERE family_id = ?',
                [familyId],
              ).first['next_device_sequence']
              as int;
      final keyEpoch = _latestKeyEpoch(row['resource_id'] as String);
      final metadata = <String, Object>{
        'protocol': 1,
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
        final envelope = RelayEnvelope(
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
            sha256.convert([...encrypted.nonce, ...encrypted.ciphertext]).bytes,
          ),
        );
        await relay.upload(envelope);
        database.transaction(() {
          database.raw.execute(
            "UPDATE outbox SET state = 'uploaded' WHERE operation_id = ?",
            [row['operation_id']],
          );
          database.raw.execute(
            'UPDATE sync_state SET next_device_sequence = ? WHERE family_id = ?',
            [sequence + 1, familyId],
          );
        });
        uploaded++;
      } finally {
        key.dispose();
      }
    }

    final state = database.raw.select(
      'SELECT server_cursor FROM sync_state WHERE family_id = ?',
      [familyId],
    ).first;
    final page = await relay.download(familyId, state['server_cursor'] as int);
    var applied = 0;
    var conflicts = 0;
    for (final envelope in page.operations) {
      if (envelope.authorDeviceId == deviceId) continue;
      _verifyDigest(envelope);
      final metadata = <String, Object>{
        'protocol': 1,
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
            additionalData: Uint8List.fromList(
              utf8.encode(jsonEncode(metadata)),
            ),
          ),
          key,
        );
        final decoded = Map<String, Object?>.from(
          jsonDecode(utf8.decode(plaintext)) as Map,
        );
        if (decoded['kind'] == 'family_created') continue;
        final event = CalendarEvent.fromJson(
          Map<String, Object?>.from(decoded['payload']! as Map),
        );
        final result = repository.applyRemote(
          operationId: envelope.operationId,
          event: event,
          vector: envelope.logicalVersion,
        );
        if (result == RemoteApplyResult.applied) applied++;
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

  int _latestKeyEpoch(String resourceId) {
    final rows = database.raw.select(
      'SELECT max(key_epoch) AS epoch FROM resource_keys WHERE resource_id = ?',
      [resourceId],
    );
    final epoch = rows.first['epoch'] as int?;
    if (epoch == null) throw StateError('No resource key is available.');
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
