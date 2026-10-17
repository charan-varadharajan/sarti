import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';

import 'package:sarti_mobile/src/core/backup/backup_service.dart';
import 'package:sarti_mobile/src/features/backup/backup_recovery.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/core/crypto/resource_crypto.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/core/ids.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/features/calendar/domain/calendar_event.dart';
import 'package:sarti_mobile/src/features/sync/sync_engine.dart';
import 'package:sodium/sodium.dart';
import 'package:timezone/data/latest.dart' as zones;

class OrderedRelay implements EncryptedRelay {
  final accepted = <RelayEnvelope>[];
  bool loseReply = false;
  @override
  Future<void> upload(RelayEnvelope envelope) async {
    final prior = accepted.where((e) => e.operationId == envelope.operationId);
    if (prior.isEmpty) {
      expect(envelope.deviceSequence, accepted.length + 1);
      accepted.add(envelope);
    } else {
      expect(envelope.ciphertext, prior.single.ciphertext);
      expect(envelope.nonce, prior.single.nonce);
    }
    if (loseReply) {
      loseReply = false;
      throw StateError('Synthetic interrupted reply');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }

  @override
  Future<RelayPage> download(String familyId, int cursor) async =>
      RelayPage([], cursor);
}

void main() {
  setUpAll(zones.initializeTimeZones);
  test('S5-HOUSEHOLD-001 scoped selection, children, private calendars and pinned writes', () {
    final db = SartiDatabase.open(':memory:', Uint8List(32));
    addTearDown(db.close);
    final repo = CalendarRepository(db, deviceId: newId(), adultId: newId());
    final a = repo.createFamily(name: 'Household A');
    final scopedA = repo.forHousehold(a.householdId);
    final privateA = scopedA.ensurePersonalCalendar();
    final b = repo.createFamily(name: 'Household B');
    final privateB = repo.ensurePersonalCalendar();
    expect(privateA, isNot(privateB));
    expect(repo.load()!.householdId, b.householdId);
    expect(scopedA.load()!.householdId, a.householdId);
    final childA = scopedA.addChild('Synthetic child', 0xffabcdef);
    final childB = repo.addChild('Synthetic child', 0xffabcdef);
    expect(childA.id, isNot(childB.id));
    expect(repo.load()!.children.single.id, childB.id);
    scopedA.saveEvent(
      CalendarEvent(
        id: newId(),
        householdId: a.householdId,
        calendarResourceId: privateA,
        title: 'Private A canary',
        localStart: DateTime(2026, 12, 1, 9),
        timezone: 'Etc/UTC',
        durationMinutes: 60,
        childIds: [],
        revision: 1,
        updatedAt: DateTime.utc(2026),
      ),
    );
    expect(repo.load()!.events, isEmpty);
    repo.selectHousehold(a.householdId);
    expect(repo.load()!.events.single.title, 'Private A canary');
    expect(repo.personalResourceId, privateA);
    expect(() => scopedA.selectHousehold(b.householdId), throwsStateError);
    expect(() => repo.selectHousehold(newId()), throwsStateError);
    expect(db.raw.select('PRAGMA foreign_key_check'), isEmpty);
  });

  test('S5-OFFLINE-001 concurrent contexts share a device sequence; timed-out envelopes remain exact', () async {
    final sodium = await SodiumInit.init();
    final db = SartiDatabase.open(':memory:', Uint8List(32));
    addTearDown(db.close);
    final device = newId();
    final repo = CalendarRepository(db, deviceId: device);
    final a = repo.createFamily();
    final b = repo.createFamily();
    for (final family in [a, b]) {
      db.setResourceKey(
        family.calendarResourceId,
        1,
        sodium.randombytes.buf(32),
      );
    }
    final relay = OrderedRelay();
    SyncEngine engine() => SyncEngine(
      database: db,
      repository: repo,
      crypto: ResourceCrypto(sodium),
      sodium: sodium,
      relay: relay,
      deviceId: device,
    );
    relay.loseReply = true;
    await expectLater(engine().synchronize(a.householdId), throwsStateError);
    final pending = db.raw.select(
      'SELECT envelope_json FROM outbox WHERE family_id=?',
      [a.householdId],
    ).single['envelope_json'];
    await expectLater(engine().synchronize(b.householdId), throwsStateError);
    expect(
      db.raw.select('SELECT envelope_json FROM outbox WHERE family_id=?', [
        a.householdId,
      ]).single['envelope_json'],
      pending,
    );
    await Future.wait([
      engine().synchronize(a.householdId),
      engine().synchronize(b.householdId),
    ]);
    expect(relay.accepted.map((e) => e.deviceSequence), [1, 2]);
    expect(relay.accepted.map((e) => e.familyId), [
      a.householdId,
      b.householdId,
    ]);
    expect(
      db.raw.select("SELECT 1 FROM outbox WHERE state='pending'"),
      isEmpty,
    );
    expect(
      db.raw
          .select('SELECT next_device_sequence FROM device_sync_state')
          .single['next_device_sequence'],
      3,
    );
    // Cursors stay contextual; selection never changes an in-flight repository.
    expect(db.raw.select('SELECT * FROM sync_state'), hasLength(2));
    expect(repo.load()!.householdId, b.householdId);
  });
  test('S5-EXPORT-001 encrypted household snapshot excludes other contexts and private keys', () async {
    final sodium = await SodiumInit.init();
    final folder = Directory.systemTemp.createTempSync(
      'sarti-scoped-snapshot-',
    );
    addTearDown(() => folder.deleteSync(recursive: true));
    final db = SartiDatabase.open('${folder.path}/source.db', Uint8List(32));
    addTearDown(db.close);
    final repo = CalendarRepository(db, deviceId: newId(), adultId: newId());
    final a = repo.createFamily(name: 'Household A');
    final aRepo = repo.forHousehold(a.householdId);
    final privateA = aRepo.ensurePersonalCalendar();
    final b = repo.createFamily(name: 'Household B private canary');
    final childB = repo.addChild('Other household child canary', 0xffabcdef);
    final privateB = repo.ensurePersonalCalendar();
    for (final id in [
      a.calendarResourceId,
      b.calendarResourceId,
      childB.id,
      privateA,
      privateB,
    ]) {
      db.setResourceKey(id, 1, sodium.randombytes.buf(32));
    }
    for (final family in [a, b]) {
      db.raw.execute(
        "INSERT INTO recovery_intents(source_operation_id,family_id,resource_id,kind,payload_json,vector_json,status,reason,original_envelope_json,server_receipt) VALUES (?,?,?,'family_created',?,?,'quarantined','lost_write_authority',?,'unknown')",
        [
          newId(),
          family.householdId,
          family.calendarResourceId,
          jsonEncode({'householdId': family.householdId}),
          jsonEncode({repo.deviceId: 1}),
          'Exact original ${family.householdId}',
        ],
      );
    }
    const phrase =
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
    final blob = await BackupRecovery.snapshot(
      database: db,
      key: Uint8List(32),
      phrase: phrase,
      sodium: sodium,
      familyId: a.householdId,
    );
    final file = File('${folder.path}/snapshot.srtbk')..writeAsBytesSync(blob);
    final result = BackupService.restoreBackup(
      backupPath: file.path,
      outputPath: '${folder.path}/restored.db',
      recoveryPhrase: phrase,
      sodium: sodium,
    );
    final restored = SartiDatabase.open(
      '${folder.path}/restored.db',
      result.databaseKey,
    );
    try {
      expect(
        restored.raw.select('SELECT id FROM households').single['id'],
        a.householdId,
      );
      expect(restored.raw.select('SELECT * FROM children'), isEmpty);
      expect(restored.raw.select('SELECT * FROM personal_calendars'), isEmpty);
      expect(
        restored.raw
            .select('SELECT resource_id FROM resource_keys')
            .map((r) => r['resource_id']),
        [a.calendarResourceId],
      );
      final preserved = restored.raw.select('SELECT * FROM recovery_intents');
      expect(preserved, hasLength(1));
      expect(preserved.single['family_id'], a.householdId);
      expect(
        preserved.single['original_envelope_json'],
        'Exact original ${a.householdId}',
      );
      expect(preserved.single['server_receipt'], 'unknown');
      expect(db.raw.select('SELECT * FROM recovery_intents'), hasLength(2));
      expect(restored.raw.select('PRAGMA foreign_key_check'), isEmpty);
      expect(repo.load()!.householdId, b.householdId);
      expect(db.resourceKey(privateB, 1), isNotNull);
    } finally {
      restored.close();
      result.databaseKey.fillRange(0, 32, 0);
    }
  });
  test('S5-MIGRATE-001 v9 SQLCipher preserves private keys and exact pending bytes', () {
    final folder = Directory.systemTemp.createTempSync('sarti-v9-migration-');
    addTearDown(() => folder.deleteSync(recursive: true));
    final path = '${folder.path}/source.db';
    final key = Uint8List.fromList(List.generate(32, (i) => i + 1));
    var db = SartiDatabase.open(path, key);
    final device = newId(), adult = newId();
    final repo = CalendarRepository(db, deviceId: device, adultId: adult);
    final family = repo.createFamily();
    final private = repo.ensurePersonalCalendar();
    db.setResourceKey(private, 1, key);
    db.raw.execute(
      "UPDATE outbox SET envelope_json='exact authenticated bytes'",
    );
    db.raw.execute('''
      DROP TABLE device_sync_state;
      ALTER TABLE recovery_intents DROP COLUMN original_envelope_json;
      ALTER TABLE recovery_intents DROP COLUMN server_receipt;
      ALTER TABLE personal_calendars RENAME TO personal_v10;
      CREATE TABLE personal_calendars (
        adult_id TEXT PRIMARY KEY,
        household_id TEXT NOT NULL REFERENCES households(id) ON DELETE CASCADE,
        resource_id TEXT NOT NULL UNIQUE
      ) STRICT;
      INSERT INTO personal_calendars SELECT * FROM personal_v10;
      DROP TABLE personal_v10;
      PRAGMA user_version=9;
    ''');
    db.close();
    db = SartiDatabase.open(path, key);
    try {
      expect(db.raw.userVersion, SartiDatabase.schemaVersion);
      final upgraded = CalendarRepository(db, deviceId: device, adultId: adult);
      expect(upgraded.personalResourceId, private);
      expect(db.resourceKey(private, 1), key);
      expect(
        db.raw
            .select('SELECT envelope_json FROM outbox')
            .single['envelope_json'],
        'exact authenticated bytes',
      );
      upgraded.createFamily();
      expect(upgraded.ensurePersonalCalendar(), isNot(private));
      expect(
        upgraded.forHousehold(family.householdId).personalResourceId,
        private,
      );
      expect(db.raw.select('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      db.close();
    }
    expect(() => SartiDatabase.open(path, Uint8List(32)), throwsA(anything));
  });
}
