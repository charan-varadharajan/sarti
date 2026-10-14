import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:sarti_mobile/src/core/network/sarti_api.dart';
import 'package:sarti_mobile/src/features/backup/family_recovery_coordinator.dart';
import 'package:sarti_mobile/src/features/backup/family_recovery_screen.dart';
import 'package:sarti_mobile/src/core/crypto/device_key_store.dart';
import 'package:sarti_mobile/src/core/crypto/resource_crypto.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/core/ids.dart';
import 'package:sarti_mobile/src/features/backup/backup_recovery.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/features/calendar/domain/calendar_event.dart';
import 'package:sarti_mobile/src/features/sync/sync_engine.dart';
import 'package:sodium/sodium.dart';
import 'package:timezone/data/latest.dart' as zones;

class _Secrets implements SecretStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    values.clear();
  }
}

class _RetainedRelay implements EncryptedRelay {
  _RetainedRelay(this.envelope);
  final RelayEnvelope envelope;
  @override
  Future<void> upload(RelayEnvelope envelope) async =>
      throw StateError('Old-device outbox must not be restored.');
  @override
  Future<RelayPage> download(String familyId, int cursor) async =>
      RelayPage(cursor < 1 ? [envelope] : [], 1);
}

class _ReviewedRelay implements EncryptedRelay {
  final operations = <RelayEnvelope>[];
  final attempts = <RelayEnvelope>[];
  bool loseReceipt = false;
  @override
  Future<void> upload(RelayEnvelope envelope) async {
    attempts.add(envelope);
    final previous = operations
        .where((e) => e.operationId == envelope.operationId)
        .firstOrNull;
    if (previous != null) {
      expect(envelope.nonce, previous.nonce);
      expect(envelope.ciphertext, previous.ciphertext);
      expect(envelope.deviceSequence, previous.deviceSequence);
    } else {
      operations.add(
        RelayEnvelope(
          protocolVersion: envelope.protocolVersion,
          serverSequence: operations.length + 1,
          operationId: envelope.operationId,
          familyId: envelope.familyId,
          resourceId: envelope.resourceId,
          authorDeviceId: envelope.authorDeviceId,
          deviceSequence: envelope.deviceSequence,
          keyEpoch: envelope.keyEpoch,
          logicalVersion: envelope.logicalVersion,
          nonce: envelope.nonce,
          ciphertext: envelope.ciphertext,
          contentDigest: envelope.contentDigest,
        ),
      );
    }
    if (loseReceipt) {
      loseReceipt = false;
      throw StateError('Synthetic lost receipt');
    }
  }

  @override
  Future<RelayPage> download(String familyId, int cursor) async => RelayPage(
    operations.where((e) => e.serverSequence > cursor).toList(),
    operations.length,
  );
}

/// Default regressions for accepted ADR-040: real encrypted recovery and relay.
void main() => familyRecoveryScenarios();

void familyRecoveryScenarios() {
  const phrase =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
  late Sodium sodium;
  late Directory dir;
  late SartiDatabase source, target;
  late CalendarRepository sourceRepo, targetRepo;
  late CalendarEvent original;
  late String family, calendar, oldDevice, newDevice, guardian;
  late Uint8List sourceKey, historicalKey, currentKey;
  late _Secrets secrets;

  setUpAll(() async {
    zones.initializeTimeZones();
    sodium = await SodiumInit.init();
  });
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('sarti-bug022-');
    sourceKey = sodium.randombytes.buf(32);
    historicalKey = sodium.randombytes.buf(32);
    currentKey = sodium.randombytes.buf(32);
    oldDevice = newId();
    newDevice = newId();
    guardian = newId();
    source = SartiDatabase.open('${dir.path}/source.db', sourceKey);
    sourceRepo = CalendarRepository(source, deviceId: oldDevice);
    final created = sourceRepo.createFamily();
    family = created.householdId;
    calendar = created.calendarResourceId;
    source.setResourceKey(calendar, 1, historicalKey);
    source.setResourceKey(calendar, 2, sodium.randombytes.buf(32));
    original = CalendarEvent(
      id: newId(),
      householdId: family,
      calendarResourceId: calendar,
      title: 'Original shared appointment',
      localStart: DateTime.utc(2026, 12, 1, 17),
      timezone: 'Etc/UTC',
      durationMinutes: 60,
      childIds: [],
      revision: 1,
      updatedAt: DateTime.utc(2026, 10, 13),
    );
    sourceRepo.saveEvent(original);
    sourceRepo.saveEvent(
      original.copyWith(title: 'Restored offline change', revision: 2),
    );
    secrets = _Secrets()
      ..values['sign-secret-v1'] = 'fresh-synthetic-device-secret';
    target = SartiDatabase.open(
      '${dir.path}/replacement.db',
      sodium.randombytes.buf(32),
    );
    final blob = await BackupRecovery.snapshot(
      database: source,
      key: sourceKey,
      phrase: phrase,
      sodium: sodium,
      familyId: family,
    );
    await BackupRecovery.stage(
      blob: blob,
      phrase: phrase,
      familyId: family,
      current: target,
      sodium: sodium,
      secrets: secrets,
    );
    final path = target.path;
    target.close();
    await BackupRecovery.activate(path, secrets);
    final recoveredKey = base64Url.decode(secrets.values['database-key-v1']!);
    target = SartiDatabase.open(path, recoveredKey);
    recoveredKey.fillRange(0, recoveredKey.length, 0);
    targetRepo = CalendarRepository(target, deviceId: newDevice);
    // Controlled current authorization/grant, not evidence of real passkeys or
    // signed provider transport. Replacement epoch is newer than both saved keys.
    target.setResourceKey(calendar, 3, currentKey);
    target.raw.execute(
      'INSERT OR REPLACE INTO resource_catalog VALUES (?,?,?,?)',
      [calendar, family, 'calendar', 3],
    );
  });
  tearDown(() {
    source.close();
    target.close();
    sourceKey.fillRange(0, sourceKey.length, 0);
    historicalKey.fillRange(0, historicalKey.length, 0);
    currentKey.fillRange(0, currentKey.length, 0);
    dir.deleteSync(recursive: true);
  });

  Future<void> restoreSourceAgain() async {
    target.close();
    target = SartiDatabase.open(
      '${dir.path}/${newId()}.db',
      sodium.randombytes.buf(32),
    );
    final blob = await BackupRecovery.snapshot(
      database: source,
      key: sourceKey,
      phrase: phrase,
      sodium: sodium,
      familyId: family,
    );
    await BackupRecovery.stage(
      blob: blob,
      phrase: phrase,
      familyId: family,
      current: target,
      sodium: sodium,
      secrets: secrets,
    );
    final path = target.path;
    target.close();
    await BackupRecovery.activate(path, secrets);
    final key = base64Url.decode(secrets.values['database-key-v1']!);
    target = SartiDatabase.open(path, key);
    key.fillRange(0, key.length, 0);
    targetRepo = CalendarRepository(target, deviceId: newDevice);
    target.setResourceKey(calendar, 3, currentKey);
  }

  SyncEngine engine(
    CalendarEvent event, {
    required int epoch,
    required String author,
    required Map<String, int> vector,
    required Uint8List keyBytes,
  }) {
    final operation = newId();
    final metadata = <String, Object>{
      'protocol': 2,
      'familyId': family,
      'resourceId': calendar,
      'keyEpoch': epoch,
      'operationId': operation,
      'authorDeviceId': author,
      'deviceSequence': 1,
      'logicalVersion': vector,
    };
    final key = SecureKey.fromList(sodium, keyBytes);
    late EncryptedResourcePayload encrypted;
    try {
      encrypted = ResourceCrypto(sodium).encrypt(
        plaintext: Uint8List.fromList(
          utf8.encode(
            jsonEncode({'kind': 'event_upserted', 'payload': event.toJson()}),
          ),
        ),
        key: key,
        metadata: metadata,
      );
    } finally {
      key.dispose();
    }
    final envelope = RelayEnvelope(
      protocolVersion: 2,
      serverSequence: 1,
      operationId: operation,
      familyId: family,
      resourceId: calendar,
      authorDeviceId: author,
      deviceSequence: 1,
      keyEpoch: epoch,
      logicalVersion: vector,
      nonce: encrypted.nonce,
      ciphertext: encrypted.ciphertext,
      contentDigest: Uint8List.fromList(
        sha256.convert([...encrypted.nonce, ...encrypted.ciphertext]).bytes,
      ),
    );
    return SyncEngine(
      database: target,
      repository: targetRepo,
      crypto: ResourceCrypto(sodium),
      sodium: sodium,
      relay: _RetainedRelay(envelope),
      deviceId: newDevice,
    );
  }

  FamilyRecoveryCoordinator coordinator(
    _ReviewedRelay relay, {
    bool Function()? allowed,
    bool Function()? resourceAvailable,
    String Function()? policyPeriod,
  }) {
    final transport = SyncEngine(
      database: target,
      repository: targetRepo,
      crypto: ResourceCrypto(sodium),
      sodium: sodium,
      relay: relay,
      deviceId: newDevice,
    );
    return FamilyRecoveryCoordinator(
      repository: targetRepo,
      listFamilies: () async => [
        RemoteFamily(
          id: family,
          role: allowed?.call() == false ? 'guardian' : 'owner',
          status: 'active',
          resources: [
            if (resourceAvailable?.call() != false)
              RemoteResource(
                id: calendar,
                kind: 'calendar',
                keyEpoch: 3,
                permission: 'admin',
              ),
          ],
        ),
      ],
      prepareKeys: () async {},
      sync: (downloadOnly) =>
          transport.synchronize(family, downloadOnly: downloadOnly),
      readPolicy: () async => {
        'period': policyPeriod?.call() ?? 'week',
        'revision': 0,
        'enabled': true,
        'can_manage': true,
      },
      onChanged: () {},
    );
  }

  test('RECOVERY-CONT-001 restored family decrypts historical relay and rejects stale overwrite', () async {
    expect(target.raw.select('SELECT * FROM outbox'), isEmpty);
    await engine(
      original,
      epoch: 1,
      author: oldDevice,
      vector: {oldDevice: 1},
      keyBytes: historicalKey,
    ).synchronize(family);
    expect(targetRepo.load()!.events.single.title, 'Restored offline change');
    expect(secrets.values['sign-secret-v1'], 'fresh-synthetic-device-secret');
  });

  test('RECOVERY-CONT-002 readable concurrent change cannot erase restored pending edit', () async {
    final incoming = original.copyWith(title: 'Guardian concurrent change');
    final result = await engine(
      incoming,
      epoch: 3,
      author: guardian,
      vector: {guardian: 1},
      keyBytes: currentKey,
    ).synchronize(family);
    expect(targetRepo.load()!.events.single.title, 'Restored offline change');
    expect(result.conflicts, 1);
    expect(targetRepo.openConflicts(), hasLength(1));
  });
  test('RECOVERY-CONT-003 reviewed retry uses new identity and exact fresh envelope without duplicate events', () async {
    final relay = _ReviewedRelay();
    final c = coordinator(relay);
    addTearDown(c.dispose);
    await c.synchronize();
    expect(c.changes, hasLength(1));
    expect(target.raw.select('SELECT * FROM outbox'), isEmpty);
    final sourceIds = source.raw
        .select('SELECT operation_id FROM outbox')
        .map((r) => r['operation_id'])
        .toSet();
    relay.loseReceipt = true;
    await expectLater(c.approve(c.changes.single), throwsStateError);
    expect(targetRepo.recoveryPending, isTrue);
    expect(c.changes.single.status, 'queued');
    target.raw.execute(
      "UPDATE outbox SET kind='event_deleted' WHERE state='pending'",
    );
    await expectLater(c.synchronize(), throwsStateError);
    expect(relay.attempts, hasLength(1));
    target.raw.execute(
      "UPDATE outbox SET kind='event_upserted' WHERE state='pending'",
    );
    await c.synchronize();
    expect(relay.operations, hasLength(1));
    expect(relay.attempts, hasLength(2));
    final sent = relay.operations.single;
    expect(sent.authorDeviceId, newDevice);
    expect(sent.keyEpoch, 3);
    expect(sourceIds.contains(sent.operationId), isFalse);
    expect(sent.logicalVersion[newDevice], 1);
    expect(targetRepo.load()!.events.single.id, original.id);
    expect(c.changes, isEmpty);
    expect(secrets.values['sign-secret-v1'], 'fresh-synthetic-device-secret');
  });
  test('RECOVERY-CONT-004 current owner/resource authorization overrides restored history', () async {
    final relay = _ReviewedRelay();
    var allowed = true, resourceAvailable = true;
    final c = coordinator(
      relay,
      allowed: () => allowed,
      resourceAvailable: () => resourceAvailable,
    );
    addTearDown(c.dispose);
    await c.synchronize();
    final reviewed = c.changes.single;
    allowed = false;
    await expectLater(c.approve(reviewed), throwsStateError);
    expect(relay.attempts, isEmpty);
    expect(targetRepo.load()!.events.single.title, 'Restored offline change');
    allowed = true;
    resourceAvailable = false;
    await expectLater(c.approve(reviewed), throwsStateError);
    expect(relay.attempts, isEmpty);
    expect(targetRepo.recoveryPending, isTrue);
    expect(() => targetRepo.saveEvent(original), throwsStateError);
  });
  test(
    'RECOVERY-CONT-005 legacy missing vectors stays readable and read-only',
    () async {
      target.raw.execute('DELETE FROM event_versions');
      targetRepo.initializeFamilyRecovery();
      final relay = _ReviewedRelay();
      final c = coordinator(relay);
      addTearDown(c.dispose);
      await expectLater(c.synchronize(), throwsStateError);
      expect(c.state!['phase'], 'blocked');
      expect(relay.attempts, isEmpty);
      expect(targetRepo.load()!.events.single.title, 'Restored offline change');
      expect(() => targetRepo.saveEvent(original), throwsStateError);
    },
  );
  test('RECOVERY-CONT-005A malformed ciphertext preserves cursor, local content and pause', () async {
    final incoming =
        engine(
              original,
              epoch: 1,
              author: oldDevice,
              vector: {oldDevice: 1},
              keyBytes: historicalKey,
            ).relay
            as _RetainedRelay;
    final e = incoming.envelope;
    final corrupt = Uint8List.fromList(e.ciphertext)..[0] ^= 1;
    final relay = _ReviewedRelay()
      ..operations.add(
        RelayEnvelope(
          protocolVersion: 2,
          serverSequence: 1,
          operationId: e.operationId,
          familyId: family,
          resourceId: calendar,
          authorDeviceId: oldDevice,
          deviceSequence: 1,
          keyEpoch: 1,
          logicalVersion: e.logicalVersion,
          nonce: e.nonce,
          ciphertext: corrupt,
          contentDigest: Uint8List.fromList(
            sha256.convert([...e.nonce, ...corrupt]).bytes,
          ),
        ),
      );
    final c = coordinator(relay);
    addTearDown(c.dispose);
    await expectLater(c.synchronize(), throwsA(anything));
    expect(
      target.raw
          .select('SELECT server_cursor FROM sync_state')
          .single['server_cursor'],
      0,
    );
    expect(targetRepo.load()!.events.single.title, 'Restored offline change');
    expect(targetRepo.recoveryPending, isTrue);
  });
  test('RECOVERY-CONT-002A explicit concurrent resolution publishes chosen version', () async {
    final incoming =
        engine(
              original.copyWith(title: 'Guardian concurrent change'),
              epoch: 3,
              author: guardian,
              vector: {guardian: 1},
              keyBytes: currentKey,
            ).relay
            as _RetainedRelay;
    final relay = _ReviewedRelay()..operations.add(incoming.envelope);
    final c = coordinator(relay);
    addTearDown(c.dispose);
    await c.synchronize();
    final conflict = targetRepo.openConflicts().single;
    await c.resolveEvent(
      conflict.id,
      useRemote: false,
      reviewedFingerprint: c.conflictFingerprint(conflict.id),
    );
    expect(targetRepo.openConflicts(), isEmpty);
    expect(c.changes, isEmpty);
    expect(targetRepo.load()!.events.single.title, 'Restored offline change');
    expect(relay.operations.last.authorDeviceId, newDevice);
    expect(relay.operations.last.logicalVersion[guardian], 1);
  });
  testWidgets(
    'RECOVERY-CONT-006 prepared review requires approval and explicit retention resume',
    (tester) async {
      final relay = _ReviewedRelay();
      final c = coordinator(relay);
      addTearDown(c.dispose);
      await c.synchronize();
      await tester.pumpWidget(
        MaterialApp(home: FamilyRecoveryScreen(coordinator: c)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('seven days'), findsOneWidget);
      expect(relay.attempts, isEmpty);
      await tester.ensureVisible(find.text('Approve recovered change'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve recovered change'));
      await tester.pumpAndSettle();
      expect(relay.operations, hasLength(1));
      expect(targetRepo.recoveryPending, isTrue);
      await tester.ensureVisible(
        find.text('Review history and resume cleanup'),
      );
      await tester.tap(find.text('Review history and resume cleanup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep paused'));
      await tester.pumpAndSettle();
      expect(targetRepo.recoveryPending, isTrue);
      await tester.tap(find.text('Review history and resume cleanup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resume calendar and cleanup'));
      await tester.pumpAndSettle();
      expect(targetRepo.recoveryPending, isFalse);
      expect(
        target.raw.select(
          "SELECT 1 FROM app_preferences WHERE key='retention-recovery-pending'",
        ),
        isEmpty,
      );
      expect(targetRepo.load()!.events.single.id, original.id);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test('RECOVERY-CONT-003A unsent creation and deletion preserve IDs after approval', () async {
    final added = original.copyWith(
      id: newId(),
      title: 'Unsent new appointment',
      revision: 1,
    );
    sourceRepo.saveEvent(added);
    sourceRepo.saveEvent(original.copyWith(deleted: true, revision: 3));
    await restoreSourceAgain();
    final relay = _ReviewedRelay();
    final c = coordinator(relay);
    addTearDown(c.dispose);
    await c.synchronize();
    expect(c.changes, hasLength(2));
    expect(relay.attempts, isEmpty);
    while (c.changes.isNotEmpty) {
      await c.approve(c.changes.first);
    }
    expect(relay.operations, hasLength(2));
    expect(
      relay.operations.map((e) => e.authorDeviceId),
      everyElement(newDevice),
    );
    expect(targetRepo.load()!.events.single.id, added.id);
    expect(
      target.raw.select('SELECT deleted FROM events WHERE id=?', [
        original.id,
      ]).single['deleted'],
      1,
    );
  });
  test('RECOVERY-CONT-007 child resource needs fresh sharing consent', () async {
    final child = sourceRepo.addChild(
      'Prepared child',
      0xffccddee,
      shareWithCalendarGuardians: true,
    );
    await restoreSourceAgain();
    final relay = _ReviewedRelay();
    final resources = <RemoteResource>[
      RemoteResource(
        id: calendar,
        kind: 'calendar',
        keyEpoch: 3,
        permission: 'admin',
      ),
    ];
    final sharing = <bool>[];
    final transport = SyncEngine(
      database: target,
      repository: targetRepo,
      crypto: ResourceCrypto(sodium),
      sodium: sodium,
      relay: relay,
      deviceId: newDevice,
    );
    final c = FamilyRecoveryCoordinator(
      repository: targetRepo,
      listFamilies: () async => [
        RemoteFamily(
          id: family,
          role: 'owner',
          status: 'active',
          resources: resources,
        ),
      ],
      prepareKeys: () async {},
      sync: (downloadOnly) =>
          transport.synchronize(family, downloadOnly: downloadOnly),
      readPolicy: () async => {
        'period': 'week',
        'revision': 0,
        'enabled': true,
        'can_manage': true,
      },
      onChanged: () {},
      newResourceKey: () => sodium.randombytes.buf(32),
      provisionResource: (id, kind, share) async {
        sharing.add(share);
        final r = RemoteResource(
          id: id,
          kind: kind,
          keyEpoch: 1,
          permission: 'admin',
        );
        resources.add(r);
        target.raw.execute('INSERT INTO resource_catalog VALUES (?,?,?,?)', [
          id,
          family,
          kind,
          1,
        ]);
        return r;
      },
    );
    addTearDown(c.dispose);
    await c.synchronize();
    final reviewed = c.changes.singleWhere((r) => r.resourceId == child.id);
    await expectLater(c.approve(reviewed), throwsStateError);
    expect(sharing, isEmpty);
    await c.authorizeResource(reviewed, share: false);
    expect(sharing, [false]);
    expect(relay.attempts, isEmpty);
    await c.approve(c.changes.singleWhere((r) => r.resourceId == child.id));
    expect(relay.operations.single.resourceId, child.id);
    expect(
      target.raw.select(
        'SELECT share_with_calendar_guardians FROM child_sync WHERE child_id=?',
        [child.id],
      ).single['share_with_calendar_guardians'],
      0,
    );
  });
  test(
    'RECOVERY-GATE-001 unreviewed outgoing mutation cannot publish',
    () async {
      final relay = _ReviewedRelay();
      final c = coordinator(relay);
      addTearDown(c.dispose);
      final row = source.raw
          .select("SELECT * FROM outbox WHERE kind='event_upserted'")
          .last;
      target.raw.execute(
        'INSERT INTO outbox(operation_id,family_id,resource_id,kind,payload_json,vector_json,created_at) VALUES (?,?,?,?,?,?,?)',
        [
          newId(),
          family,
          calendar,
          row['kind'],
          row['payload_json'],
          row['vector_json'],
          row['created_at'],
        ],
      );
      await expectLater(c.synchronize(), throwsStateError);
      expect(relay.attempts, isEmpty);
      expect(targetRepo.recoveryPending, isTrue);
    },
  );
  test(
    'RECOVERY-CONT-006A policy change invalidates prior cleanup approval',
    () async {
      var period = 'week';
      final relay = _ReviewedRelay();
      final c = coordinator(relay, policyPeriod: () => period);
      addTearDown(c.dispose);
      await c.synchronize();
      await c.approve(c.changes.single);
      final reviewed = c.historyFingerprint;
      period = 'month';
      await expectLater(c.resumeCleanup(reviewed), throwsStateError);
      expect(targetRepo.recoveryPending, isTrue);
      await c.resumeCleanup(c.historyFingerprint);
      expect(targetRepo.recoveryPending, isFalse);
    },
  );
  test('RECOVERY-CONT-005B re-export after lost receipt retains one fresh review intent', () async {
    final relay = _ReviewedRelay();
    final c = coordinator(relay);
    addTearDown(c.dispose);
    await c.synchronize();
    relay.loseReceipt = true;
    await expectLater(c.approve(c.changes.single), throwsStateError);
    final oldQueued = target.raw
        .select("SELECT * FROM outbox WHERE state='pending'")
        .single['operation_id'];
    // A new replacement must discard former envelope bindings, retaining intent.
    target.transaction(() {
      targetRepo.initializeFamilyRecovery();
      target.raw.execute('DELETE FROM outbox');
      target.raw.execute('DELETE FROM sync_state');
    });
    expect(targetRepo.recoveredChanges(), hasLength(1));
    expect(targetRepo.recoveredChanges().single.status, 'pending');
    newDevice = newId();
    targetRepo = CalendarRepository(target, deviceId: newDevice);
    final next = coordinator(relay);
    addTearDown(next.dispose);
    await next.synchronize();
    await next.approve(next.changes.single);
    expect(relay.operations, hasLength(2));
    expect(relay.operations.last.operationId, isNot(oldQueued));
    expect(targetRepo.load()!.events, hasLength(1));
    expect(next.changes, isEmpty);
  });
  test(
    'RECOVERY-SCOPE-001 cross-family catalog rejects staged activation',
    () async {
      final foreign = newId();
      source.raw.execute('INSERT INTO resource_catalog VALUES (?,?,?,?)', [
        newId(),
        foreign,
        'calendar',
        1,
      ]);
      final blob = await BackupRecovery.snapshot(
        database: source,
        key: sourceKey,
        phrase: phrase,
        sodium: sodium,
        familyId: family,
      );
      final empty = SartiDatabase.open(
        '${dir.path}/scope-empty.db',
        sodium.randombytes.buf(32),
      );
      final fresh = _Secrets();
      try {
        await expectLater(
          BackupRecovery.stage(
            blob: blob,
            phrase: phrase,
            familyId: family,
            current: empty,
            sodium: sodium,
            secrets: fresh,
          ),
          throwsStateError,
        );
        expect(empty.raw.select('SELECT * FROM households'), isEmpty);
        expect(fresh.values.containsKey('backup-recovery-pending-v1'), isFalse);
        expect(File('${empty.path}.recovery').existsSync(), isFalse);
      } finally {
        empty.close();
      }
    },
  );
}
