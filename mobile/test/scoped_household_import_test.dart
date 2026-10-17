import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/core/crypto/resource_crypto.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/core/ids.dart';
import 'package:sarti_mobile/src/features/backup/backup_recovery.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_controller.dart';
import 'package:sarti_mobile/src/features/sync/sync_engine.dart';
import 'package:sodium/sodium.dart';
import 'package:timezone/data/latest.dart' as zones;

const _phrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

class _HeldRelay implements EncryptedRelay {
  final began = Completer<void>(), release = Completer<void>();
  final envelopes = <RelayEnvelope>[];
  @override
  Future<void> upload(RelayEnvelope envelope) async {
    envelopes.add(envelope);
    if (!began.isCompleted) began.complete();
    await release.future;
  }

  @override
  Future<RelayPage> download(String id, int cursor) async =>
      RelayPage([], cursor);
}

void main() {
  setUpAll(zones.initializeTimeZones);
  test('S5-RECOVERY-002 import B preserves A live key, exact in-flight envelopes, device sequence and private scope', () async {
    final sodium = await SodiumInit.init();
    final folder = Directory.systemTemp.createTempSync('sarti-import-');
    addTearDown(() => folder.deleteSync(recursive: true));
    final aKey = sodium.randombytes.buf(32), bKey = sodium.randombytes.buf(32);
    final aDb = SartiDatabase.open('${folder.path}/a.db', aKey);
    final bDb = SartiDatabase.open('${folder.path}/b.db', bKey);
    addTearDown(aDb.close);
    addTearDown(bDb.close);
    final device = newId(), adult = newId(), guardian = newId();
    final aRepo = CalendarRepository(aDb, deviceId: device, adultId: adult);
    final bRepo = CalendarRepository(bDb, deviceId: newId(), adultId: adult);
    final a = aRepo.createFamily(name: 'A', ownerName: 'Guardian in A');
    final b = bRepo.createFamily(name: 'B', ownerName: 'Guardian in B');
    for (final db in [aDb, bDb]) {
      db.raw.execute('UPDATE guardians SET id=?', [guardian]);
    }
    final aController = CalendarController(aRepo, timezone: 'Etc/UTC');
    final bController = CalendarController(bRepo, timezone: 'Etc/UTC');
    addTearDown(aController.dispose);
    addTearDown(bController.dispose);
    aController.save(
      title: 'A unsent canary',
      localStart: DateTime(2026, 12, 1),
      durationMinutes: 60,
      childIds: [],
      pickupGuardianId: guardian,
    );
    aController.save(
      title: 'A private canary',
      localStart: DateTime(2026, 12, 2),
      durationMinutes: 60,
      childIds: [],
      adultAppointment: true,
    );
    bController.save(
      title: 'B restored canary',
      localStart: DateTime(2026, 12, 3),
      durationMinutes: 60,
      childIds: [],
      pickupGuardianId: guardian,
    );
    bController.save(
      title: 'B private excluded canary',
      localStart: DateTime(2026, 12, 4),
      durationMinutes: 60,
      childIds: [],
      adultAppointment: true,
    );
    final privateA = aRepo.personalResourceId!;
    final privateKey = sodium.randombytes.buf(32);
    aDb.setResourceKey(a.calendarResourceId, 1, sodium.randombytes.buf(32));
    aDb.setResourceKey(privateA, 1, privateKey);
    bDb.setResourceKey(b.calendarResourceId, 1, sodium.randombytes.buf(32));
    bDb.setResourceKey(
      bRepo.personalResourceId!,
      1,
      sodium.randombytes.buf(32),
    );
    aDb.raw.execute(
      "UPDATE outbox SET state='uploaded' WHERE kind='family_created'",
    );
    aDb.raw.execute('INSERT INTO device_sync_state VALUES (?,29)', [device]);
    aDb.raw.execute(
      'INSERT INTO sync_state(family_id,server_cursor,next_device_sequence) VALUES (?,44,29)',
      [a.householdId],
    );
    final blob = await BackupRecovery.snapshot(
      database: bDb,
      key: bKey,
      phrase: _phrase,
      sodium: sodium,
      familyId: b.householdId,
    );
    final relay = _HeldRelay();
    final engine = SyncEngine(
      database: aDb,
      repository: aRepo,
      crypto: ResourceCrypto(sodium),
      sodium: sodium,
      relay: relay,
      deviceId: device,
    );
    final sync = engine.synchronize(a.householdId);
    await relay.began.future;
    final before = jsonEncode(
      aDb.raw
          .select(
            'SELECT * FROM outbox WHERE family_id=? ORDER BY operation_id',
            [a.householdId],
          )
          .map((r) => Map<String, Object?>.from(r))
          .toList(),
    );
    await BackupRecovery.importHousehold(
      blob: blob,
      phrase: _phrase,
      familyId: b.householdId,
      current: aDb,
      sodium: sodium,
    );
    expect(
      jsonEncode(
        aDb.raw
            .select(
              'SELECT * FROM outbox WHERE family_id=? ORDER BY operation_id',
              [a.householdId],
            )
            .map((r) => Map<String, Object?>.from(r))
            .toList(),
      ),
      before,
    );
    expect(aRepo.load()!.householdId, a.householdId);
    expect(aRepo.personalResourceId, privateA);
    expect(aDb.resourceKey(privateA, 1), privateKey);
    expect(
      aDb.raw
          .select('SELECT next_device_sequence FROM device_sync_state')
          .single['next_device_sequence'],
      29,
    );
    final imported = aRepo.forHousehold(b.householdId);
    expect(imported.load()!.events.single.title, 'B restored canary');
    expect(imported.load()!.events.single.pickupGuardianId, guardian);
    expect(imported.load()!.guardians.single.name, 'Guardian in B');
    expect(aRepo.load()!.guardians.single.name, 'Guardian in A');
    expect(imported.personalResourceId, isNull);
    expect(imported.recoveryPending, isTrue);
    expect(aRepo.retentionPaused, isFalse);
    expect(
      aDb.raw.select('SELECT * FROM outbox WHERE family_id=?', [b.householdId]),
      isEmpty,
    );
    expect(
      aDb.raw.select('SELECT * FROM recovery_intents WHERE family_id=?', [
        b.householdId,
      ]),
      isNotEmpty,
    );
    relay.release.complete();
    final report = await sync;
    expect(
      relay.envelopes.map((e) => e.deviceSequence),
      List.generate(report.uploaded, (i) => 29 + i),
    );
    expect(
      aDb.raw
          .select('SELECT next_device_sequence FROM device_sync_state')
          .single['next_device_sequence'],
      29 + report.uploaded,
    );
    expect(
      aDb.raw.select('SELECT server_cursor FROM sync_state WHERE family_id=?', [
        a.householdId,
      ]).single['server_cursor'],
      44,
    );
    expect(aDb.raw.select('PRAGMA foreign_key_check'), isEmpty);
    // The live SQLCipher key did not become the imported snapshot's key.
    final reopen = SartiDatabase.open(aDb.path, aKey);
    reopen.close();
    expect(() => SartiDatabase.open(aDb.path, bKey), throwsA(anything));
  });

  test('S5-RECOVERY-003 wrong key, corrupt/foreign snapshot and identity collisions roll back without touching A', () async {
    final sodium = await SodiumInit.init();
    final folder = Directory.systemTemp.createTempSync(
      'sarti-import-negative-',
    );
    addTearDown(() => folder.deleteSync(recursive: true));
    final key = sodium.randombytes.buf(32);
    final current = SartiDatabase.open('${folder.path}/current.db', key);
    final sourceKey = sodium.randombytes.buf(32);
    final source = SartiDatabase.open('${folder.path}/source.db', sourceKey);
    addTearDown(current.close);
    addTearDown(source.close);
    final aRepo = CalendarRepository(current, deviceId: newId());
    final bRepo = CalendarRepository(source, deviceId: newId());
    final a = aRepo.createFamily(name: 'A');
    final b = bRepo.createFamily(name: 'B');
    final ca = CalendarController(aRepo, timezone: 'Etc/UTC');
    final cb = CalendarController(bRepo, timezone: 'Etc/UTC');
    addTearDown(ca.dispose);
    addTearDown(cb.dispose);
    final collision = newId();
    for (final c in [ca, cb]) {
      c.save(
        id: collision,
        title: c.family!.name,
        localStart: DateTime(2026, 12, 1),
        durationMinutes: 60,
        childIds: [],
      );
    }
    final blob = await BackupRecovery.snapshot(
      database: source,
      key: sourceKey,
      phrase: _phrase,
      sodium: sodium,
      familyId: b.householdId,
    );
    String state() => jsonEncode([
      for (final table in [
        'households',
        'events',
        'outbox',
        'resource_keys',
        'app_preferences',
        'recovery_state',
        'recovery_intents',
      ])
        current.raw
            .select('SELECT * FROM $table')
            .map((r) => Map<String, Object?>.from(r))
            .toList(),
    ]);
    final before = state();
    for (final attempt in [
      () => BackupRecovery.importHousehold(
        blob: blob,
        phrase: 'wrong words',
        familyId: b.householdId,
        current: current,
        sodium: sodium,
      ),
      () => BackupRecovery.importHousehold(
        blob: Uint8List(48),
        phrase: _phrase,
        familyId: b.householdId,
        current: current,
        sodium: sodium,
      ),
      () => BackupRecovery.importHousehold(
        blob: blob,
        phrase: _phrase,
        familyId: newId(),
        current: current,
        sodium: sodium,
      ),
      () => BackupRecovery.importHousehold(
        blob: blob,
        phrase: _phrase,
        familyId: b.householdId,
        current: current,
        sodium: sodium,
      ),
    ]) {
      await expectLater(attempt(), throwsA(anything));
      expect(state(), before);
      expect(aRepo.load()!.householdId, a.householdId);
      expect(current.raw.select('PRAGMA foreign_key_check'), isEmpty);
    }
  });
}
