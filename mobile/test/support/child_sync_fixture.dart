import 'dart:typed_data';

import 'package:sarti_mobile/src/core/crypto/device_key_store.dart';
import 'package:sarti_mobile/src/core/crypto/resource_crypto.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/core/ids.dart';
import 'package:sarti_mobile/src/core/network/sarti_api.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/features/sync/resource_key_sync.dart';
import 'package:sarti_mobile/src/features/sync/sync_engine.dart';
import 'package:sodium/sodium.dart';

/// Prepared authorized devices, independent SQLCipher DBs and real libsodium.
/// The relay/directory are fixtures; no production authentication is simulated
/// as evidence of passkey or provider compatibility.
class ChildSyncFixture {
  ChildSyncFixture(this.sodium) {
    a = ChildSyncDevice(this, newId());
    b = ChildSyncDevice(this, newId());
    familyId = newId();
    calendarId = newId();
    a.repository.createFamily(
      familyId: familyId,
      calendarResourceId: calendarId,
    );
    b.database.raw.execute(
      'INSERT INTO households(id, display_name, created_at, calendar_resource_id) VALUES (?, ?, ?, ?)',
      [
        familyId,
        'Prepared family',
        DateTime.now().toUtc().toIso8601String(),
        calendarId,
      ],
    );
    resources[calendarId] = RemoteResource(
      id: calendarId,
      kind: 'calendar',
      keyEpoch: 1,
    );
    a.database.setResourceKey(calendarId, 1, sodium.randombytes.buf(32));
  }
  final Sodium sodium;
  late final ChildSyncDevice a, b;
  late final String familyId, calendarId;
  final Map<String, RemoteResource> resources = {};
  final List<ResourceKeyGrant> grants = [];
  final List<RelayEnvelope> operations = [];
  final Set<String> denied = {};
  final Map<String, String> childPermissions = {};
  int nextServerSequence = 0;
  String calendarGuardianPermission = 'admin';
  bool loseNextReceipt = false;
  bool loseNextGrantReceipt = false;
  bool offline = false;
  final List<RelayEnvelope> attempts = [];
  bool reverseDownload = false;
  List<RelayEnvelope>? injected;

  void close() {
    a.close();
    b.close();
  }
}

class ChildSyncDevice implements ResourceKeyApi, EncryptedRelay {
  ChildSyncDevice(this.fixture, this.id) {
    final box = fixture.sodium.crypto.box.keyPair();
    final sign = fixture.sodium.crypto.sign.keyPair();
    keys = DeviceKeyMaterial(
      databaseKey: fixture.sodium.secureRandom(32),
      encryptionPublicKey: box.publicKey,
      encryptionSecretKey: box.secretKey,
      signingPublicKey: sign.publicKey,
      signingSecretKey: sign.secretKey,
      deviceId: newId(),
    );
    database = SartiDatabase.open(':memory:', keys.databaseKey.extractBytes());
    repository = CalendarRepository(database, deviceId: id);
    keySync = ResourceKeySync(
      database: database,
      repository: repository,
      sodium: fixture.sodium,
      keys: keys,
      deviceId: id,
      api: this,
    );
    engine = SyncEngine(
      database: database,
      repository: repository,
      crypto: ResourceCrypto(fixture.sodium),
      sodium: fixture.sodium,
      relay: this,
      deviceId: id,
    );
  }
  final ChildSyncFixture fixture;
  final String id;
  late final DeviceKeyMaterial keys;
  late final SartiDatabase database;
  late final CalendarRepository repository;
  late final ResourceKeySync keySync;
  late final SyncEngine engine;

  Future<SyncReport> sync() async {
    if (fixture.offline) throw StateError('Fixture offline.');
    await keySync.prepare(fixture.familyId);
    return engine.synchronize(fixture.familyId);
  }

  void close() {
    database.close();
    keys.dispose();
  }

  @override
  Future<List<RemoteFamily>> listFamilies() async => [
    RemoteFamily(
      id: fixture.familyId,
      role: id == fixture.a.id ? 'owner' : 'guardian',
      status: 'active',
      resources: fixture.resources.values.toList(),
    ),
  ];
  @override
  Future<RemoteResource> provisionChild(
    String familyId,
    String resourceId, {
    bool shareWithCalendarGuardians = false,
  }) async {
    if (!fixture.resources.containsKey(resourceId) &&
        shareWithCalendarGuardians) {
      fixture.childPermissions[resourceId] = 'read';
    }
    return fixture.resources.putIfAbsent(
      resourceId,
      () => RemoteResource(id: resourceId, kind: 'child_profile', keyEpoch: 1),
    );
  }

  @override
  Future<List<ResourceDevice>> resourceDevices(
    String familyId,
    String resourceId,
  ) async {
    if (fixture.denied.contains(id) ||
        (id == fixture.b.id &&
            resourceId != fixture.calendarId &&
            !fixture.childPermissions.containsKey(resourceId))) {
      throw const SartiApiException(403);
    }
    return [fixture.a, fixture.b]
        .where(
          (d) =>
              !fixture.denied.contains(d.id) &&
              (d.id == fixture.a.id ||
                  resourceId == fixture.calendarId ||
                  fixture.childPermissions.containsKey(resourceId)),
        )
        .map(
          (d) => ResourceDevice(
            deviceId: d.id,
            encryptionPublicKey: d.keys.encryptionPublicKey,
            signingPublicKey: d.keys.signingPublicKey,
            permission: d.id == fixture.a.id
                ? 'admin'
                : resourceId == fixture.calendarId
                ? fixture.calendarGuardianPermission
                : fixture.childPermissions[resourceId]!,
            hasCurrentGrant: fixture.grants.any(
              (g) =>
                  g.resourceId == resourceId &&
                  g.keyEpoch == fixture.resources[resourceId]!.keyEpoch &&
                  g.recipientDeviceId == d.id,
            ),
          ),
        )
        .toList();
  }

  @override
  Future<List<ResourceKeyGrant>> keyGrants() async => fixture.grants
      .where(
        (g) =>
            g.recipientDeviceId == id &&
            g.keyEpoch == fixture.resources[g.resourceId]!.keyEpoch &&
            !fixture.denied.contains(id) &&
            !fixture.denied.contains(g.granterDeviceId),
      )
      .toList();
  @override
  Future<void> uploadKeyGrant(String familyId, ResourceKeyGrant grant) async {
    final first = fixture.grants
        .where(
          (g) =>
              g.resourceId == grant.resourceId && g.keyEpoch == grant.keyEpoch,
        )
        .firstOrNull;
    if (first != null &&
        first.granterDeviceId != id &&
        !fixture.grants.any(
          (g) =>
              g.resourceId == grant.resourceId &&
              g.keyEpoch == grant.keyEpoch &&
              g.recipientDeviceId == id &&
              g.granterDeviceId == first.granterDeviceId,
        )) {
      throw const SartiApiException(409);
    }
    final existing = fixture.grants
        .where(
          (g) =>
              g.resourceId == grant.resourceId &&
              g.keyEpoch == grant.keyEpoch &&
              g.recipientDeviceId == grant.recipientDeviceId,
        )
        .firstOrNull;
    if (existing != null) throw const SartiApiException(409);
    fixture.grants.add(grant);
    if (fixture.loseNextGrantReceipt) {
      fixture.loseNextGrantReceipt = false;
      throw StateError('Fixture lost self-grant response after acceptance.');
    }
  }

  @override
  Future<void> upload(RelayEnvelope envelope) async {
    fixture.attempts.add(envelope);
    if (fixture.offline) throw StateError('Fixture offline.');
    if (!fixture.operations.any((e) => e.operationId == envelope.operationId)) {
      if (envelope.keyEpoch !=
          fixture.resources[envelope.resourceId]!.keyEpoch) {
        throw RelayConflict();
      }
      fixture.operations.add(
        copyEnvelope(envelope, serverSequence: ++fixture.nextServerSequence),
      );
    }
    if (fixture.loseNextReceipt) {
      fixture.loseNextReceipt = false;
      throw StateError('Fixture lost response after accepting operation.');
    }
  }

  @override
  Future<RelayPage> download(String familyId, int cursor) async {
    var rows =
        fixture.injected ??
        fixture.operations.where((e) => e.serverSequence > cursor).toList();
    final next = rows.fold(
      cursor,
      (int n, e) => e.serverSequence > n ? e.serverSequence : n,
    );
    if (fixture.reverseDownload) rows = rows.reversed.toList();
    return RelayPage(rows, next);
  }
}

RelayEnvelope copyEnvelope(
  RelayEnvelope e, {
  int? serverSequence,
  String? familyId,
  String? resourceId,
  Uint8List? ciphertext,
  Uint8List? digest,
}) => RelayEnvelope(
  protocolVersion: e.protocolVersion,
  serverSequence: serverSequence ?? e.serverSequence,
  operationId: e.operationId,
  familyId: familyId ?? e.familyId,
  resourceId: resourceId ?? e.resourceId,
  authorDeviceId: e.authorDeviceId,
  deviceSequence: e.deviceSequence,
  keyEpoch: e.keyEpoch,
  logicalVersion: e.logicalVersion,
  nonce: e.nonce,
  ciphertext: ciphertext ?? e.ciphertext,
  contentDigest: digest ?? e.contentDigest,
);
