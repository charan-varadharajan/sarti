import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/core/auth/native_passkey_adapter.dart';
import 'package:sarti_mobile/src/core/crypto/device_key_store.dart';
import 'package:sarti_mobile/src/core/crypto/resource_crypto.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/core/ids.dart';
import 'package:sarti_mobile/src/core/network/sarti_api.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_controller.dart';
import 'package:sarti_mobile/src/features/guardians/guardian_coordinator.dart';
import 'package:sarti_mobile/src/features/guardians/invitation_links.dart';
import 'package:sarti_mobile/src/features/sync/resource_key_sync.dart';
import 'package:sarti_mobile/src/features/sync/sync_engine.dart';
import 'package:sodium/sodium.dart';
import 'package:timezone/data/latest.dart' as tz_data;

const fixtureUrl = String.fromEnvironment('SARTI_GUARDIAN_TEST_URL');

class _Passkeys implements NativePasskeyAdapter {
  @override
  Future<Map<String, dynamic>> register(Map<String, dynamic> publicKey) async =>
      {'id': newId(), 'challenge': publicKey['challenge']};
  @override
  Future<Map<String, dynamic>> authenticate(
    Map<String, dynamic> publicKey,
  ) async => throw UnimplementedError();
}

void main() {
  test(
    'GUARD-HTTP-001 real HTTP/PostgreSQL approval and encrypted retained-state handoff',
    () async {
      tz_data.initializeTimeZones();
      final sodium = await SodiumInit.init();
      final apis = <SartiApiClient>[],
          dbs = <SartiDatabase>[],
          keys = <DeviceKeyMaterial>[];
      final repos = <CalendarRepository>[], sessions = <AuthenticatedSession>[];
      final coordinators = <GuardianCoordinator>[];
      addTearDown(() {
        for (final c in coordinators) {
          c.dispose();
        }
        for (final api in apis) {
          api.close();
        }
        for (final db in dbs) {
          db.close();
        }
        for (final key in keys) {
          key.dispose();
        }
      });
      for (var i = 0; i < 2; i++) {
        final box = sodium.crypto.box.keyPair(),
            sign = sodium.crypto.sign.keyPair();
        final key = DeviceKeyMaterial(
          databaseKey: sodium.secureRandom(32),
          encryptionPublicKey: box.publicKey,
          encryptionSecretKey: box.secretKey,
          signingPublicKey: sign.publicKey,
          signingSecretKey: sign.secretKey,
          deviceId: newId(),
        );
        keys.add(key);
        final api = SartiApiClient(Uri.parse(fixtureUrl));
        apis.add(api);
        final session = await api.registerPasskey(_Passkeys(), key);
        sessions.add(session);
        final db = SartiDatabase.open(
          ':memory:',
          key.databaseKey.extractBytes(),
        );
        dbs.add(db);
        repos.add(CalendarRepository(db, deviceId: session.deviceId));
      }
      final family = repos[0].createFamily(
        name: 'Prepared household',
        ownerName: 'Owner',
      );
      final familyId = family.householdId,
          calendarId = family.calendarResourceId;
      dbs[0].setResourceKey(calendarId, 1, sodium.randombytes.buf(32));
      final child = repos[0].addChild(
        'Mia',
        0xff00ff00,
        cloudAlias: 'green-fox-1234',
      );
      final hidden = repos[0].addChild(
        'Jithu',
        0xff0000ff,
        cloudAlias: 'blue-fox-1234',
      );
      CalendarController(repos[0], timezone: 'America/Vancouver').save(
        title: 'Prepared swimming',
        localStart: DateTime(2026, 10, 13, 9),
        durationMinutes: 120,
        childIds: [child.id, hidden.id],
      );
      for (var i = 0; i < 2; i++) {
        final index = i;
        final keySync = ResourceKeySync(
          database: dbs[i],
          repository: repos[i],
          sodium: sodium,
          keys: keys[i],
          deviceId: sessions[i].deviceId,
          api: apis[i],
        );
        final engine = SyncEngine(
          database: dbs[i],
          repository: repos[i],
          crypto: ResourceCrypto(sodium),
          sodium: sodium,
          relay: apis[i],
          deviceId: sessions[i].deviceId,
        );
        coordinators.add(
          GuardianCoordinator(
            database: dbs[i],
            repository: repos[i],
            api: apis[i],
            keys: keys[i],
            synchronize: () async {
              if (index == 0) {
                await apis[0].provisionFamily(
                  familyId: familyId,
                  calendarResourceId: calendarId,
                );
              }
              if (repos[index].load() == null) return;
              await keySync.prepare(familyId);
              await engine.synchronize(familyId);
            },
          ),
        );
      }
      final owner = coordinators[0], guardian = coordinators[1];
      await owner.refresh();
      await owner.create();
      expect(owner.invitation, isNotNull);
      await guardian.accept(invitationLink(owner.invitation!.token));
      expect(guardian.family!.status, 'pending');
      expect(repos[1].load(), isNull);
      expect(await apis[1].keyGrants(), isEmpty);
      // Expire only this fixture family's relay. Keys and local source survive.
      final http = HttpClient();
      try {
        final request = await http.postUrl(
          Uri.parse('$fixtureUrl/__fixture__/expire'),
        );
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode({'family_id': familyId}));
        final response = await request.close();
        await response.drain<void>();
        expect(response.statusCode, 204);
      } finally {
        http.close();
      }
      await owner.refresh();
      final review = owner.invitations.singleWhere(
        (i) => i.status == 'pending',
      );
      expect(
        guardianVerificationCode(
          guardianKeyDigest(
            review.signingPublicKey!,
            review.encryptionPublicKey!,
          ),
        ),
        guardian.ownCode,
      );
      final profile = owner.family!.resources
          .singleWhere((r) => r.kind == 'family_profile')
          .id;
      final access = {calendarId: 'read', profile: 'read', child.id: 'read'};
      await owner.approve(review, access, 'Other parent');
      expect(
        owner.message,
        'Guardian approved. The encrypted calendar has been shared.',
      );
      await guardian.refresh();
      expect(guardian.ready, isTrue);
      final received = repos[1].load()!;
      expect(received.name, 'Prepared household');
      expect(received.children.map((c) => c.name), ['Mia']);
      expect(received.events.single.title, 'Prepared swimming');
      expect(received.events.single.durationMinutes, 120);
      expect(received.guardians.map((g) => g.name), contains('Other parent'));
      expect(dbs[1].resourceKey(hidden.id, 1), isNull);
      final before = await apis[0].download(familyId, 0);
      await owner.approve(review, access, 'Other parent');
      expect(
        (await apis[0].download(familyId, 0)).operations,
        hasLength(before.operations.length),
      );
      await expectLater(
        apis[1].createInvitation(familyId),
        throwsA(
          isA<SartiApiException>().having((e) => e.statusCode, 'status', 403),
        ),
      );
      await owner.revoke(
        owner.invitations.singleWhere((i) => i.id == review.id),
      );
      expect(await apis[1].keyGrants(), isEmpty);
      expect(dbs[1].resourceKey(calendarId, 2), isNull);
      await expectLater(
        apis[1].download(familyId, 0),
        throwsA(
          isA<SartiApiException>().having((e) => e.statusCode, 'status', 404),
        ),
      );
    },
    skip: fixtureUrl.isEmpty
        ? 'Run the explicit guardian PostgreSQL/HTTP host'
        : false,
  );
}
