import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/core/crypto/resource_crypto.dart';
import 'package:sarti_mobile/src/core/network/sarti_api.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_controller.dart';
import 'package:sodium/sodium.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import 'support/child_sync_fixture.dart';

void main() {
  late Sodium sodium;
  late ChildSyncFixture f;
  setUpAll(() async {
    sodium = await SodiumInit.init();
    tz_data.initializeTimeZones();
  });
  setUp(() => f = ChildSyncFixture(sodium));
  tearDown(() => f.close());

  void advanceEpoch() {
    f.resources[f.calendarId] = RemoteResource(
      id: f.calendarId,
      kind: 'calendar',
      keyEpoch: 2,
    );
  }

  test(
    'REPLACE-SEC-001 retained old key cannot decrypt future writes',
    () async {
      await f.a.keySync.prepare(f.familyId);
      await f.b.keySync.prepare(f.familyId);
      final oldKey = SecureKey.fromList(
        sodium,
        f.b.database.resourceKey(f.calendarId, 1)!,
      );
      addTearDown(oldKey.dispose);
      f.denied.add(f.b.id);
      advanceEpoch();
      await f.a.keySync.prepare(f.familyId);
      final newKey = SecureKey.fromList(
        sodium,
        f.a.database.resourceKey(f.calendarId, 2)!,
      );
      addTearDown(newKey.dispose);
      expect(
        sodium.memcmp(oldKey.extractBytes(), newKey.extractBytes()),
        isFalse,
      );
      final crypto = ResourceCrypto(sodium);
      final encrypted = crypto.encrypt(
        plaintext: Uint8List.fromList([1, 2, 3]),
        key: newKey,
        metadata: {'keyEpoch': 2},
      );
      expect(crypto.decrypt(encrypted, newKey), [1, 2, 3]);
      expect(() => crypto.decrypt(encrypted, oldKey), throwsA(anything));
      expect(
        f.grants.where((g) => g.keyEpoch == 2).map((g) => g.recipientDeviceId),
        [f.a.id],
      );
      expect(await f.b.keyGrants(), isEmpty);
      await expectLater(
        f.b.resourceDevices(f.familyId, f.calendarId),
        throwsA(isA<SartiApiException>()),
      );
      await f.b.keySync.prepare(f.familyId);
      expect(f.b.database.resourceKey(f.calendarId, 2), isNull);
      expect(
        f.b.database.resourceKey(f.calendarId, 1),
        orderedEquals(oldKey.extractBytes()),
      );
    },
  );

  test(
    'REPLACE-SYNC-001 restored admin establishes only unclaimed advanced epoch',
    () async {
      // Prepared restored content, fresh keys and empty historical key cache.
      f.denied.add(f.a.id);
      advanceEpoch();
      expect(f.b.database.resourceKey(f.calendarId, 1), isNull);
      await f.b.keySync.prepare(f.familyId);
      final key = f.b.database.resourceKey(f.calendarId, 2)!;
      expect(key, hasLength(32));
      expect(f.grants.single.recipientDeviceId, f.b.id);
      CalendarController(f.b.repository, timezone: 'America/Vancouver').save(
        title: 'Prepared future activity',
        localStart: DateTime(2026, 10, 12, 9),
        durationMinutes: 60,
        childIds: const [],
      );
      final report = await f.b.engine.synchronize(f.familyId);
      expect(report.uploaded, greaterThan(0));
      expect(f.operations.every((e) => e.keyEpoch == 2), isTrue);
      await f.b.keySync.prepare(f.familyId);
      expect(f.b.database.resourceKey(f.calendarId, 2), orderedEquals(key));
      expect(f.grants, hasLength(1));
    },
  );

  test('REPLACE-SYNC-002 lost self-grant response recovers established key without replacement', () async {
    f.denied.add(f.a.id);
    advanceEpoch();
    f.loseNextGrantReceipt = true;
    await expectLater(f.b.keySync.prepare(f.familyId), throwsStateError);
    expect(f.b.database.resourceKey(f.calendarId, 2), isNull);
    expect(f.grants, hasLength(1));
    final wrapped = Uint8List.fromList(f.grants.single.wrappedKey);
    await f.b.keySync.prepare(f.familyId);
    expect(f.b.database.resourceKey(f.calendarId, 2), hasLength(32));
    expect(f.grants, hasLength(1));
    expect(f.grants.single.wrappedKey, orderedEquals(wrapped));
  });

  test('REPLACE-SEC-002 absent initial key or established advanced key is never invented', () async {
    f.denied.add(f.a.id);
    await f.b.keySync.prepare(f.familyId);
    expect(f.b.database.resourceKey(f.calendarId, 1), isNull);
    expect(f.grants, isEmpty);
    f.denied.remove(f.a.id);
    f.denied.add(f.b.id);
    advanceEpoch();
    await f.a.keySync.prepare(f.familyId);
    f.denied.remove(f.b.id);
    await f.b.keySync.prepare(f.familyId);
    expect(f.b.database.resourceKey(f.calendarId, 2), isNull);
    expect(f.grants, hasLength(1));
    CalendarController(f.b.repository, timezone: 'America/Vancouver').save(
      title: 'Pending prepared activity',
      localStart: DateTime(2026, 10, 12, 9),
      durationMinutes: 60,
      childIds: const [],
    );
    await expectLater(f.b.engine.synchronize(f.familyId), throwsStateError);
    expect(f.operations, isEmpty);
    expect(
      f.b.database.raw.select("SELECT * FROM outbox WHERE state = 'pending'"),
      isNotEmpty,
    );
  });
}
