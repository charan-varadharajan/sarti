import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/core/crypto/resource_crypto.dart';
import 'package:sarti_mobile/src/core/ids.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/core/network/sarti_api.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/features/calendar/domain/calendar_event.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_controller.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_screen.dart';
import 'package:sarti_mobile/src/features/sync/resource_key_sync.dart';
import 'package:sarti_mobile/src/features/sync/sync_engine.dart';
import 'package:sodium/sodium.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'support/child_sync_fixture.dart';
import 'support/sarti_test_harness.dart';

void main() {
  late Sodium sodium;
  late ChildSyncFixture f;
  setUpAll(() async {
    sodium = await SodiumInit.init();
    tz_data.initializeTimeZones();
  });
  setUp(() {
    f = ChildSyncFixture(sodium);
  });
  tearDown(() {
    f.close();
  });

  test('CHILD-SYNC-001 offline child and event arrive with labels and colours, exactly once', () async {
    f.offline = true;
    final child = f.a.repository.addChild(
      'Mia',
      0xff8e6cef,
      cloudAlias: 'hanging-frog-4821',
      shareWithCalendarGuardians: true,
    );
    f.a.repository.saveEvent(event(f, child.id));
    await expectLater(f.a.sync(), throwsStateError);
    expect(f.a.repository.load()!.children.single.name, 'Mia');
    f.offline = false;
    await f.a.sync();
    f.reverseDownload =
        true; // Event can arrive before its separate child profile.
    final report = await f.b.sync();
    expect(report.applied, 2);
    final family = f.b.repository.load()!;
    expect(family.children.single.name, 'Mia');
    expect(family.children.single.colorArgb, child.colorArgb);
    expect(family.children.single.cloudAlias, child.cloudAlias);
    expect(family.events.single.childIds, [child.id]);
    expect(
      f.b.database.resourceKey(child.id, 1),
      f.a.database.resourceKey(child.id, 1),
    );
    expect(
      f.b.database.resourceKey(child.id, 1),
      isNot(f.a.database.resourceKey(f.calendarId, 1)),
    );
    expect((await f.b.sync()).applied, 0);
    expect(f.operations, hasLength(3));
    // Server-visible objects contain opaque identifiers, ciphertext and sealed keys only.
    for (final op in f.operations) {
      expect(
        utf8.decode(op.ciphertext, allowMalformed: true),
        isNot(contains('Mia')),
      );
    }
  });

  test('CHILD-SYNC-002 lost receipt retries the identical ciphertext with a recreated engine', () async {
    final child = f.a.repository.addChild(
      'Mia',
      0xff8e6cef,
      shareWithCalendarGuardians: true,
    );
    f.loseNextReceipt = true;
    await expectLater(f.a.sync(), throwsStateError);
    final original = f.attempts.single;
    final recreated = SyncEngine(
      database: f.a.database,
      repository: f.a.repository,
      crypto: ResourceCrypto(sodium),
      sodium: sodium,
      relay: f.a,
      deviceId: f.a.id,
    );
    await recreated.synchronize(f.familyId);
    final retried = f.attempts[1];
    expect(retried.operationId, original.operationId);
    expect(retried.nonce, original.nonce);
    expect(retried.ciphertext, original.ciphertext);
    expect(retried.deviceSequence, original.deviceSequence);
    expect(f.operations.map((e) => e.operationId).toSet(), hasLength(2));
    await f.b.sync();
    expect(f.b.repository.load()!.children.single.id, child.id);
  });

  for (final accepted in [false, true]) {
    test(
      'CHILD-SYNC-006 pending envelope survives rotation (accepted=$accepted)',
      () async {
        final child = f.a.repository.addChild(
          'Mia',
          0xff8e6cef,
          shareWithCalendarGuardians: true,
        );
        await f.a.sync();
        await f.b.sync();
        f.a.repository.queueChildProfile(child.id);
        if (accepted) {
          f.loseNextReceipt = true;
        } else {
          f.offline = true;
        }
        await expectLater(f.a.engine.synchronize(f.familyId), throwsStateError);
        final old = f.attempts.last;
        f.offline = false;
        f.resources[child.id] = RemoteResource(
          id: child.id,
          kind: 'child_profile',
          keyEpoch: 2,
        );
        await f.a.sync();
        await f.b.sync();
        expect(
          f.a.database.raw.select("SELECT 1 FROM outbox WHERE state='pending'"),
          isEmpty,
        );
        expect(f.b.repository.load()!.children.single.name, 'Mia');
        final retries = f.attempts
            .where((e) => e.operationId == old.operationId)
            .toList();
        expect(retries[1].ciphertext, old.ciphertext);
        if (!accepted) {
          expect(retries.last.keyEpoch, 2);
          expect(retries.last.operationId, old.operationId);
          expect(retries.last.deviceSequence, old.deviceSequence);
        }
      },
    );
  }

  test('CHILD-SYNC-005 new resource grant replays profiles passed by an earlier cursor', () async {
    await f.a.sync();
    await f.b.sync();
    final child = f.a.repository.addChild(
      'Mia',
      0xff8e6cef,
      shareWithCalendarGuardians: true,
    );
    await f.a.sync();
    f.b.database.raw.execute(
      'UPDATE sync_state SET server_cursor = ? WHERE family_id = ?',
      [f.operations.last.serverSequence, f.familyId],
    );
    expect(f.b.repository.load()!.children, isEmpty);
    await f.b.sync();
    expect(f.b.repository.load()!.children.single.id, child.id);
    expect((await f.b.sync()).applied, 0);
  });

  test(
    'CHILD-SEC-001 grants are signed, recipient-bound and fail closed',
    () async {
      final child = f.a.repository.addChild(
        'Mia',
        0xff8e6cef,
        shareWithCalendarGuardians: true,
      );
      await f.a.sync();
      final resource = f.resources[child.id]!;
      final devices = await f.b.resourceDevices(f.familyId, child.id);
      final valid = f.grants.singleWhere(
        (g) => g.resourceId == child.id && g.recipientDeviceId == f.b.id,
      );
      ResourceKeyGrant altered({
        String? recipient,
        String? granter,
        int? epoch,
        Uint8List? wrapped,
        Uint8List? signature,
      }) => ResourceKeyGrant(
        resourceId: valid.resourceId,
        keyEpoch: epoch ?? valid.keyEpoch,
        recipientDeviceId: recipient ?? valid.recipientDeviceId,
        granterDeviceId: granter ?? valid.granterDeviceId,
        wrappedKey: wrapped ?? valid.wrappedKey,
        signature: signature ?? valid.signature,
      );
      for (final invalid in [
        altered(recipient: f.a.id),
        altered(granter: newId()),
        altered(epoch: 2),
        altered(wrapped: Uint8List.fromList(valid.wrappedKey)..[0] ^= 1),
        altered(signature: Uint8List(64)),
      ]) {
        expect(
          () => f.b.keySync.acceptGrant(invalid, resource, devices),
          throwsA(anything),
        );
        expect(f.b.database.resourceKey(child.id, 1), isNull);
      }
      expect(
        () => sodium.crypto.box.sealOpen(
          cipherText: valid.wrappedKey,
          publicKey: f.a.keys.encryptionPublicKey,
          secretKey: f.a.keys.encryptionSecretKey,
        ),
        throwsA(anything),
      );
      f.b.keySync.acceptGrant(valid, resource, devices);
      final original = f.b.database.resourceKey(child.id, 1)!;
      final otherKey = sodium.randombytes.buf(32);
      final wrapped = sodium.crypto.box.seal(
        message: otherKey,
        publicKey: f.b.keys.encryptionPublicKey,
      );
      final unsigned = altered(wrapped: wrapped);
      final conflicting = altered(
        wrapped: wrapped,
        signature: sodium.crypto.sign.detached(
          message: resourceGrantMessage(unsigned),
          secretKey: f.a.keys.signingSecretKey,
        ),
      );
      expect(
        () => f.b.keySync.acceptGrant(conflicting, resource, devices),
        throwsStateError,
      );
      expect(f.b.database.resourceKey(child.id, 1), original);
      expect(
        () => f.b.keySync.acceptGrant(
          valid,
          resource,
          devices.where((d) => d.deviceId != f.a.id).toList(),
        ),
        throwsStateError,
      );
    },
  );

  test(
    'CHILD-SEC-002 revoked device receives no keys for future children',
    () async {
      f.denied.add(f.b.id);
      final child = f.a.repository.addChild(
        'Mia',
        0xff8e6cef,
        shareWithCalendarGuardians: true,
      );
      await f.a.sync();
      expect(f.grants.where((g) => g.recipientDeviceId == f.b.id), isEmpty);
      await expectLater(f.b.sync(), throwsA(anything));
      expect(f.b.database.resourceKey(child.id, 1), isNull);
      expect(f.b.repository.load()!.children, isEmpty);
    },
  );

  test('CHILD-SEC-003 scope, malformed profile and conflicting create cannot overwrite', () async {
    final child = f.a.repository.addChild(
      'Mia',
      0xff8e6cef,
      cloudAlias: 'hanging-frog-4821',
      shareWithCalendarGuardians: true,
    );
    await f.a.sync();
    await f.b.sync();
    final payload = {
      'id': child.id,
      'householdId': f.familyId,
      'name': 'Mia',
      'colorArgb': child.colorArgb,
      'cloudAlias': child.cloudAlias,
    };
    for (final invalid in [
      {...payload, 'householdId': newId()},
      {...payload, 'id': newId()},
      {...payload, 'name': 'Changed'},
      {...payload, 'colorArgb': -1},
      {...payload, 'unexpected': 'value'},
    ]) {
      expect(
        () => f.b.repository.applyRemoteChild(
          operationId: newId(),
          familyId: f.familyId,
          resourceId: child.id,
          keyEpoch: 1,
          payload: invalid,
        ),
        throwsA(anything),
      );
    }
    expect(f.b.repository.load()!.children.single.name, 'Mia');
    final op = f.operations.first;
    f.injected = [copyEnvelope(op, familyId: newId())];
    await expectLater(f.b.sync(), throwsStateError);
    final childOp = f.operations.singleWhere((o) => o.resourceId == child.id);
    f.injected = [
      copyEnvelope(
        childOp,
        ciphertext: Uint8List.fromList(childOp.ciphertext)..[0] ^= 1,
      ),
    ];
    await expectLater(f.b.sync(), throwsStateError);
    // Recomputed digest still cannot bypass AEAD authentication.
    final tampered = f.injected!.single;
    f.injected = [
      copyEnvelope(
        tampered,
        digest: Uint8List.fromList(
          sha256.convert([...tampered.nonce, ...tampered.ciphertext]).bytes,
        ),
      ),
    ];
    await expectLater(f.b.sync(), throwsA(anything));
  });

  test(
    'CHILD-SEC-004 calendar-key writer cannot masquerade as a child resource',
    () async {
      await f.a.sync();
      await f.b.sync();
      final childId = f.calendarId;
      final metadata = <String, Object>{
        'protocol': 1,
        'familyId': f.familyId,
        'resourceId': childId,
        'keyEpoch': 1,
        'operationId': newId(),
        'authorDeviceId': f.a.id,
        'deviceSequence': 2,
        'logicalVersion': {f.a.id: 1},
      };
      final key = SecureKey.fromList(
        sodium,
        f.a.database.resourceKey(childId, 1)!,
      );
      final encrypted = ResourceCrypto(sodium).encrypt(
        key: key,
        metadata: metadata,
        plaintext: Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'kind': 'child_created',
              'payload': {
                'id': childId,
                'householdId': f.familyId,
                'name': 'Forged',
                'colorArgb': 1,
                'cloudAlias': 'bright-otter-7314',
              },
            }),
          ),
        ),
      );
      key.dispose();
      f.injected = [
        RelayEnvelope(
          serverSequence: 2,
          operationId: metadata['operationId']! as String,
          familyId: f.familyId,
          resourceId: childId,
          authorDeviceId: f.a.id,
          deviceSequence: 2,
          keyEpoch: 1,
          logicalVersion: {f.a.id: 1},
          nonce: encrypted.nonce,
          ciphertext: encrypted.ciphertext,
          contentDigest: Uint8List.fromList(
            sha256.convert([...encrypted.nonce, ...encrypted.ciphertext]).bytes,
          ),
        ),
      ];
      await expectLater(f.b.sync(), throwsStateError);
      expect(f.b.repository.load()!.children, isEmpty);
    },
  );

  test(
    'CHILD-SYNC-003 legacy local children are queued once after provisioning',
    () async {
      final child = f.a.repository.addChild(
        'Mia',
        0xff8e6cef,
        shareWithCalendarGuardians: true,
      );
      f.a.database.raw.execute(
        "DELETE FROM outbox WHERE kind = 'child_created'",
      );
      f.a.database.raw.execute('DELETE FROM child_sync');
      // Legacy migration never invents sharing consent; this fixture explicitly grants read access.
      f.childPermissions[child.id] = 'read';
      await f.a.sync();
      await f.a.sync();
      await f.b.sync();
      expect(f.b.repository.load()!.children.single.id, child.id);
      expect(f.operations.where((o) => o.resourceId == child.id), hasLength(1));
    },
  );

  test(
    'CHILD-UNIT-001 invalid child creation rolls back without an outbox entry',
    () {
      final before = f.a.database.raw.select('SELECT * FROM outbox').length;
      expect(
        () => f.a.repository.addChild('', 1, shareWithCalendarGuardians: true),
        throwsArgumentError,
      );
      expect(
        () => f.a.repository.addChild(
          'Mia',
          -1,
          shareWithCalendarGuardians: true,
        ),
        throwsArgumentError,
      );
      expect(f.a.repository.load()!.children, isEmpty);
      expect(
        f.a.database.raw.select('SELECT * FROM outbox'),
        hasLength(before),
      );
    },
  );

  test(
    'CHILD-SEC-005 canonical grant message matches the backend wire vector',
    () {
      final grant = ResourceKeyGrant(
        resourceId: '11111111-1111-4111-8111-111111111111',
        keyEpoch: 7,
        recipientDeviceId: '22222222-2222-4222-8222-222222222222',
        granterDeviceId: '33333333-3333-4333-8333-333333333333',
        wrappedKey: Uint8List.fromList(List.generate(80, (i) => i)),
        signature: Uint8List(64),
      );
      expect(
        resourceGrantMessage(grant)
            .map((v) => v.toRadixString(16).padLeft(2, '0'))
            .join(),
        '53415254492d4752414e542d5631001111111111114111811111111111111100000000000000072222222222224222822222222222222233333333333343338333333333333333c56705fea5b110b8dc63688533ced21167e628017387c885423b835a55edd5ef',
      );
    },
  );

  test('CHILD-SYNC-004 rotated epoch converges and revoked device receives no future key', () async {
    final child = f.a.repository.addChild(
      'Mia',
      0xff8e6cef,
      shareWithCalendarGuardians: true,
    );
    await f.a.sync();
    await f.b.sync();
    f.childPermissions[child.id] = 'admin';
    final old = f.a.database.resourceKey(child.id, 1)!;
    f.resources[child.id] = RemoteResource(
      id: child.id,
      kind: 'child_profile',
      keyEpoch: 2,
    );
    await Future.wait([
      f.a.keySync.prepare(f.familyId),
      f.b.keySync.prepare(f.familyId),
    ]);
    // A racing loser waits for the winning admin's grant on its next pass.
    await f.a.sync();
    await f.b.sync();
    expect(
      f.a.database.resourceKey(child.id, 2),
      f.b.database.resourceKey(child.id, 2),
    );
    expect(f.a.database.resourceKey(child.id, 2), isNot(old));
    f.denied.add(f.b.id);
    f.resources[child.id] = RemoteResource(
      id: child.id,
      kind: 'child_profile',
      keyEpoch: 3,
    );
    await f.a.sync();
    expect(
      f.grants.where(
        (g) =>
            g.resourceId == child.id &&
            g.keyEpoch == 3 &&
            g.recipientDeviceId == f.b.id,
      ),
      isEmpty,
    );
    expect(f.b.database.resourceKey(child.id, 3), isNull);
  });

  test('CHILD-MIG-001 v5 to v6 preserves encrypted child, event and pending writes', () {
    final dir = Directory.systemTemp.createTempSync('sarti-child-migration-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/fixture.db';
    final key = sodium.randombytes.buf(32);
    var db = SartiDatabase.open(path, key);
    final repo = CalendarRepository(db, deviceId: newId());
    final family = repo.createFamily();
    final child = repo.addChild('Mia migration', 0xff8e6cef);
    repo.saveEvent(
      CalendarEvent(
        id: newId(),
        householdId: family.householdId,
        calendarResourceId: family.calendarResourceId,
        title: 'Private swimming',
        localStart: DateTime.now(),
        timezone: 'America/Vancouver',
        durationMinutes: 60,
        childIds: [child.id],
        revision: 1,
        updatedAt: DateTime.now(),
      ),
    );
    db.raw.execute(
      'DROP TABLE child_profile_versions; DROP TABLE appointment_shares; DROP TABLE personal_calendars; DROP TABLE event_participants; DROP TABLE participant_profiles; DROP TABLE child_sync; DROP TABLE resource_catalog; ALTER TABLE children DROP COLUMN is_placeholder; ALTER TABLE outbox DROP COLUMN envelope_json; PRAGMA user_version = 5;',
    );
    db.close();
    db = SartiDatabase.open(path, key);
    expect(db.raw.userVersion, SartiDatabase.schemaVersion);
    final migrated = CalendarRepository(db, deviceId: newId()).load()!;
    expect(migrated.children.single.name, 'Mia migration');
    expect(migrated.events.single.childIds, [child.id]);
    expect(
      db.raw.select("SELECT * FROM outbox WHERE state='pending'"),
      hasLength(3),
    );
    db.close();
    expect(
      utf8.decode(File(path).readAsBytesSync(), allowMalformed: true),
      isNot(contains('Mia migration')),
    );
    expect(
      () => SartiDatabase.open(path, sodium.randombytes.buf(32)),
      throwsA(anything),
    );
  });

  testWidgets(
    'CHILD-MOB-001 prepared calendar adds a child without network prerequisites',
    (tester) async {
      final harness = SartiTestHarness.create();
      addTearDown(harness.close);
      await harness.pumpCalendar(tester);
      await tester.tap(find.byTooltip('Add child'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Lina');
      await tester.ensureVisible(find.byKey(const Key('share-child-profile')));
      await tester.tap(find.byKey(const Key('share-child-profile')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(
        harness.controller.family!.children.any((c) => c.name == 'Lina'),
        isTrue,
      );
      final row = harness.database.raw.select(
        "SELECT * FROM outbox WHERE kind = 'child_created'",
      );
      expect(row, hasLength(3));
      expect(row.every((r) => r['state'] == 'pending'), isTrue);
      final childId = harness.controller.family!.children
          .singleWhere((c) => c.name == 'Lina')
          .id;
      expect(
        harness.database.raw.select(
          'SELECT share_with_calendar_guardians FROM child_sync WHERE child_id = ?',
          [childId],
        ).single['share_with_calendar_guardians'],
        1,
      );
    },
  );

  testWidgets(
    'CHILD-MOB-002 synced child label and colour render on the receiving calendar',
    (tester) async {
      final child = f.a.repository.addChild(
        'Mia',
        0xff8e6cef,
        shareWithCalendarGuardians: true,
      );
      f.a.repository.saveEvent(event(f, child.id));
      await f.a.sync();
      await f.b.sync();
      final controller = CalendarController(
        f.b.repository,
        timezone: 'America/Vancouver',
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(home: CalendarScreen(controller: controller)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Show agenda'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Mia'), findsOneWidget);
      expect(
        tester
            .widget<CircleAvatar>(find.byType(CircleAvatar).first)
            .backgroundColor,
        const Color(0xff8e6cef),
      );
    },
  );
}

CalendarEvent event(ChildSyncFixture f, String childId) {
  final today = tz.TZDateTime.now(tz.getLocation('America/Vancouver'));
  return CalendarEvent(
    id: newId(),
    householdId: f.familyId,
    calendarResourceId: f.calendarId,
    title: 'Swimming',
    localStart: DateTime(today.year, today.month, today.day, 17),
    timezone: 'America/Vancouver',
    durationMinutes: 60,
    childIds: [childId],
    revision: 1,
    updatedAt: DateTime.now().toUtc(),
  );
}
