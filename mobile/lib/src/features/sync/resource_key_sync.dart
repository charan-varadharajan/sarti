import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sarti_mobile/src/core/crypto/device_key_store.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/core/ids.dart';
import 'package:sarti_mobile/src/core/network/sarti_api.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sodium/sodium.dart';

/// The existing SARTI-GRANT-V1 wire format, shared with the server verifier.
Uint8List resourceGrantMessage(ResourceKeyGrant grant) {
  List<int> uuidBytes(String id) {
    if (!isResourceId(id)) throw StateError('Invalid grant identity.');
    final hex = id.replaceAll('-', '');
    return List.generate(
      16,
      (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
    );
  }

  if (grant.keyEpoch <= 0) throw StateError('Invalid key epoch.');
  final epoch = ByteData(8)..setUint64(0, grant.keyEpoch, Endian.big);
  return Uint8List.fromList([
    ...utf8.encode('SARTI-GRANT-V1\u0000'),
    ...uuidBytes(grant.resourceId),
    ...epoch.buffer.asUint8List(),
    ...uuidBytes(grant.recipientDeviceId),
    ...uuidBytes(grant.granterDeviceId),
    ...sha256.convert(grant.wrappedKey).bytes,
  ]);
}

class ResourceKeySync {
  ResourceKeySync({
    required this.database,
    required this.repository,
    required this.sodium,
    required this.keys,
    required this.deviceId,
    required this.api,
  });
  final SartiDatabase database;
  final CalendarRepository repository;
  final Sodium sodium;
  final DeviceKeyMaterial keys;
  final String
  deviceId; // Authenticated server identity, not the installation UUID.
  final ResourceKeyApi api;

  Future<void> prepare(String familyId, {bool recoveryOnly = false}) async {
    final families = await api.listFamilies();
    final family = families
        .where((f) => f.id == familyId && f.status == 'active')
        .single;
    final resources = {
      for (final r in family.resources)
        if (!recoveryOnly || r.kind != 'personal_calendar') r.id: r,
    };
    if (!recoveryOnly && repository.adultId != null) {
      final personal = resources.values
          .where((r) => r.kind == 'personal_calendar')
          .toList();
      if (personal.length > 1) throw StateError('Ambiguous personal resource.');
      if (personal.isNotEmpty) {
        final id = personal.single.id;
        final previous = repository.personalResourceId;
        database.transaction(() {
          if (previous != null && previous != id) {
            if (database.raw.select(
              "SELECT 1 FROM outbox WHERE resource_id=? AND state='uploaded'",
              [previous],
            ).isNotEmpty) {
              throw StateError('Private resource recovery requires review.');
            }
            final pending = database.raw.select(
              'SELECT operation_id,payload_json FROM outbox WHERE resource_id=?',
              [previous],
            );
            for (final row in pending) {
              final payload = Map<String, Object?>.from(
                jsonDecode(row['payload_json'] as String) as Map,
              );
              payload['calendarResourceId'] = id;
              database.raw.execute(
                'UPDATE outbox SET resource_id=?,payload_json=?,envelope_json=NULL WHERE operation_id=?',
                [id, jsonEncode(payload), row['operation_id']],
              );
            }
            database.raw.execute(
              'UPDATE events SET calendar_resource_id=? WHERE calendar_resource_id=?',
              [id, previous],
            );
            database.raw.execute(
              'DELETE FROM resource_keys WHERE resource_id=?',
              [previous],
            );
          }
          database.raw.execute(
            'INSERT OR REPLACE INTO personal_calendars VALUES (?,?,?)',
            [repository.adultId, familyId, id],
          );
        });
      }
    }
    final children = database.raw.select(
      'SELECT id FROM children WHERE household_id = ? AND is_placeholder = 0',
      [familyId],
    );
    for (final child in children) {
      final id = child['id'] as String;
      if (!recoveryOnly && !resources.containsKey(id)) {
        if (family.role != 'owner') {
          continue; // Server provisioning is owner-only.
        }
        // Persist before provisioning: crash/retry must never lose a published key.
        if (database.resourceKey(id, 1) == null) {
          database.setResourceKey(id, 1, sodium.randombytes.buf(32));
        }
        final choice = database.raw.select(
          'SELECT share_with_calendar_guardians FROM child_sync WHERE child_id = ?',
          [id],
        );
        resources[id] = await api.provisionChild(
          familyId,
          id,
          shareWithCalendarGuardians:
              choice.isNotEmpty &&
              choice.single['share_with_calendar_guardians'] == 1,
        );
      }
    }
    if (!recoveryOnly && api is ExtendedResourceApi) {
      final extended = api as ExtendedResourceApi;
      final personal = database.raw.select(
        'SELECT resource_id FROM personal_calendars WHERE household_id=? AND adult_id=?',
        [familyId, repository.adultId],
      );
      final participants = database.raw.select(
        "SELECT id FROM participant_profiles WHERE household_id=? AND (kind='pet' OR adult_id=?)",
        [familyId, repository.adultId],
      );
      for (final (id, kind) in [
        for (final row in personal)
          (row['resource_id'] as String, 'personal_calendar'),
        for (final row in participants)
          (row['id'] as String, 'participant_profile'),
      ]) {
        if (!resources.containsKey(id)) {
          if (database.resourceKey(id, 1) == null) {
            database.setResourceKey(id, 1, sodium.randombytes.buf(32));
          }
          resources[id] = await extended.provisionResource(
            familyId,
            id,
            kind,
            shareWithCalendarGuardians: kind == 'participant_profile',
          );
        }
      }
    }
    for (final resource in resources.values) {
      final previous = database.raw.select(
        'SELECT family_id, kind FROM resource_catalog WHERE resource_id = ?',
        [resource.id],
      );
      if (previous.isNotEmpty &&
          (previous.single['family_id'] != familyId ||
              previous.single['kind'] != resource.kind)) {
        throw StateError('Conflicting resource metadata.');
      }
      database.raw.execute(
        'INSERT OR REPLACE INTO resource_catalog VALUES (?, ?, ?, ?)',
        [resource.id, familyId, resource.kind, resource.keyEpoch],
      );
    }
    final grants = await api.keyGrants();
    for (final resource in resources.values) {
      if (!{
        'child_profile',
        'calendar',
        'family_profile',
        'personal_calendar',
        'participant_profile',
      }.contains(resource.kind)) {
        continue;
      }
      List<ResourceDevice> devices;
      try {
        devices = await api.resourceDevices(familyId, resource.id);
      } on SartiApiException catch (error) {
        if (error.statusCode == 403 || error.statusCode == 404) continue;
        rethrow;
      }
      final self = devices.where((d) => d.deviceId == deviceId).single;
      for (final grant in grants.where((g) => g.resourceId == resource.id)) {
        acceptGrant(grant, resource, devices);
      }
      var claimedEpoch = false;
      var key = database.resourceKey(resource.id, resource.keyEpoch);
      if (recoveryOnly &&
          key != null &&
          !self.hasCurrentGrant &&
          devices.any((d) => d.hasCurrentGrant)) {
        throw StateError(
          'Wait for a verified grant of the established current key.',
        );
      }
      final hasPreviousKey = database.raw.select(
        'SELECT 1 FROM resource_keys WHERE resource_id = ? AND key_epoch < ?',
        [resource.id, resource.keyEpoch],
      ).isNotEmpty;
      // A valid older snapshot may lack current-epoch keys. An admin may claim
      // an advanced, unclaimed epoch; never invent a missing initial-epoch key
      // or replace an established key. The server serializes concurrent claims.
      final unclaimedRecoveryEpoch =
          resource.keyEpoch > 1 &&
          !devices.any((device) => device.hasCurrentGrant);
      if (key == null &&
          self.permission == 'admin' &&
          (hasPreviousKey ||
              unclaimedRecoveryEpoch ||
              (resource.kind == 'family_profile' &&
                  family.role == 'owner' &&
                  resource.keyEpoch == 1 &&
                  !devices.any((d) => d.hasCurrentGrant)))) {
        final candidate = sodium.randombytes.buf(32);
        try {
          // The first self-grant claims this epoch under the server resource
          // lock. A concurrent admin must receive that established key first.
          await _sendGrant(familyId, resource, self, candidate);
          database.setResourceKey(resource.id, resource.keyEpoch, candidate);
          key = Uint8List.fromList(candidate);
          claimedEpoch = true;
        } on SartiApiException catch (error) {
          if (error.statusCode != 409) rethrow;
        } finally {
          candidate.fillRange(0, candidate.length, 0);
        }
      }
      if (key == null) continue; // Wait for an authorized current-epoch grant.
      if (self.permission == 'admin') {
        final recipients =
            devices
                .where(
                  (d) =>
                      !d.hasCurrentGrant &&
                      !(claimedEpoch && d.deviceId == deviceId),
                )
                .toList()
              ..sort(
                (a, b) => a.deviceId == deviceId
                    ? -1
                    : b.deviceId == deviceId
                    ? 1
                    : a.deviceId.compareTo(b.deviceId),
              );
        for (final recipient in recipients) {
          await _sendGrant(familyId, resource, recipient, key);
        }
      }
      if (!recoveryOnly &&
          resource.kind == 'child_profile' &&
          children.any((c) => c['id'] == resource.id) &&
          self.permission == 'admin') {
        final marker = database.raw.select(
          'SELECT key_epoch FROM child_sync WHERE child_id = ?',
          [resource.id],
        );
        final previous = marker.isEmpty
            ? -1
            : marker.single['key_epoch'] as int;
        if (previous != resource.keyEpoch) {
          database.transaction(() {
            // Existing pending creations already contain the profile. For a
            // rotated epoch or legacy local-only row, publish a fresh snapshot.
            if (previous != 0) repository.queueChildProfile(resource.id);
            database.raw.execute(
              'INSERT INTO child_sync(child_id, key_epoch) VALUES (?, ?) ON CONFLICT(child_id) DO UPDATE SET key_epoch=excluded.key_epoch',
              [resource.id, resource.keyEpoch],
            );
          });
        }
      }
    }
  }

  Future<void> _sendGrant(
    String familyId,
    RemoteResource resource,
    ResourceDevice recipient,
    Uint8List key,
  ) async {
    final wrapped = sodium.crypto.box.seal(
      message: key,
      publicKey: recipient.encryptionPublicKey,
    );
    final unsigned = ResourceKeyGrant(
      resourceId: resource.id,
      keyEpoch: resource.keyEpoch,
      recipientDeviceId: recipient.deviceId,
      granterDeviceId: deviceId,
      wrappedKey: wrapped,
      signature: Uint8List(0),
    );
    await api.uploadKeyGrant(
      familyId,
      ResourceKeyGrant(
        resourceId: unsigned.resourceId,
        keyEpoch: unsigned.keyEpoch,
        recipientDeviceId: unsigned.recipientDeviceId,
        granterDeviceId: deviceId,
        wrappedKey: wrapped,
        signature: sodium.crypto.sign.detached(
          message: resourceGrantMessage(unsigned),
          secretKey: keys.signingSecretKey,
        ),
      ),
    );
  }

  void acceptGrant(
    ResourceKeyGrant grant,
    RemoteResource resource,
    List<ResourceDevice> devices,
  ) {
    final granter = devices
        .where(
          (d) => d.deviceId == grant.granterDeviceId && d.permission == 'admin',
        )
        .firstOrNull;
    if (grant.resourceId != resource.id ||
        grant.keyEpoch != resource.keyEpoch ||
        grant.recipientDeviceId != deviceId ||
        granter == null ||
        !devices.any((d) => d.deviceId == deviceId) ||
        grant.wrappedKey.length != 80 ||
        !sodium.crypto.sign.verifyDetached(
          message: resourceGrantMessage(grant),
          signature: grant.signature,
          publicKey: granter.signingPublicKey,
        )) {
      throw StateError('The resource key grant is not authorized.');
    }
    final key = sodium.crypto.box.sealOpen(
      cipherText: grant.wrappedKey,
      publicKey: keys.encryptionPublicKey,
      secretKey: keys.encryptionSecretKey,
    );
    try {
      if (key.length != 32) throw StateError('Invalid resource key size.');
      final previous = database.resourceKey(resource.id, resource.keyEpoch);
      if (previous != null && !sodium.memcmp(previous, key)) {
        throw StateError(
          'Conflicting resource keys require administrator recovery.',
        );
      }
      database.transaction(() {
        database.setResourceKey(resource.id, resource.keyEpoch, key);
        if (previous == null) {
          // A profile may have been filtered before its permission/key arrived.
          // Replay the bounded relay; durable operation IDs prevent duplicates.
          database.raw.execute(
            '''UPDATE sync_state SET server_cursor = 0
            WHERE family_id IN (SELECT family_id FROM resource_catalog WHERE resource_id = ?)''',
            [resource.id],
          );
        }
      });
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }
}
