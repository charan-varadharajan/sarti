import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/core/crypto/resource_crypto.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/core/ids.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/features/calendar/domain/calendar_event.dart';
import 'package:sarti_mobile/src/features/calendar/domain/recurrence.dart';
import 'package:sarti_mobile/src/features/sync/sync_engine.dart';
import 'package:sodium/sodium.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:timezone/data/latest.dart' as tz_data;

void main() {
  setUpAll(tz_data.initializeTimeZones);

  test(
    'weekly recurrence preserves wall time across DST and honors interval',
    () {
      final event = CalendarEvent(
        id: newId(),
        householdId: newId(),
        calendarResourceId: newId(),
        title: 'Swimming',
        localStart: DateTime(2026, 3, 1, 17),
        timezone: 'America/Vancouver',
        durationMinutes: 60,
        childIds: const [],
        recurrence: const RecurrenceRule(
          frequency: RecurrenceFrequency.weekly,
          interval: 2,
          weekdays: {DateTime.sunday},
          count: 3,
        ),
        revision: 1,
        updatedAt: DateTime.utc(2026),
      );

      final occurrences = occurrencesBetween(
        event,
        DateTime.utc(2026, 2, 28),
        DateTime.utc(2026, 4, 30),
      );

      expect(occurrences.map((item) => item.startsAt.day), [1, 15, 29]);
      expect(occurrences.map((item) => item.startsAt.hour), everyElement(17));
      expect(occurrences[0].startsAt.timeZoneOffset, const Duration(hours: -8));
      expect(occurrences[1].startsAt.timeZoneOffset, const Duration(hours: -7));
    },
  );

  test('encrypted migration preserves content and rejects a wrong key', () {
    final directory = Directory.systemTemp.createTempSync('sarti-migration-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}/calendar.db';
    final key = Uint8List.fromList(List<int>.generate(32, (index) => index));
    final hex = key
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    final old = sqlite.sqlite3.open(path);
    old.execute('PRAGMA key = "x\'$hex\'"');
    old.execute('''
      CREATE TABLE households(id TEXT PRIMARY KEY, display_name TEXT NOT NULL, created_at TEXT NOT NULL) STRICT;
      CREATE TABLE outbox(operation_id TEXT PRIMARY KEY, family_id TEXT NOT NULL, resource_id TEXT NOT NULL, kind TEXT NOT NULL, payload_json TEXT NOT NULL, vector_json TEXT NOT NULL, state TEXT NOT NULL, created_at TEXT NOT NULL) STRICT;
      CREATE TABLE conflicts(id TEXT PRIMARY KEY, resource_id TEXT NOT NULL, local_operation_id TEXT NOT NULL, remote_operation_id TEXT NOT NULL, local_payload_json TEXT NOT NULL, remote_payload_json TEXT NOT NULL, status TEXT NOT NULL, created_at TEXT NOT NULL, UNIQUE(local_operation_id, remote_operation_id)) STRICT;
      CREATE TABLE sync_state(family_id TEXT PRIMARY KEY, server_cursor INTEGER NOT NULL DEFAULT 0) STRICT;
      CREATE TABLE private_events(id TEXT PRIMARY KEY, title TEXT NOT NULL) STRICT;
      INSERT INTO households VALUES ('family', 'Family', '2026-01-01T00:00:00Z');
      INSERT INTO outbox VALUES ('operation', 'family', 'calendar', 'family_created', '{}', '{}', 'uploaded', '2026-01-01T00:00:00Z');
      INSERT INTO private_events VALUES ('event', 'Private swimming lesson');
      PRAGMA user_version = 2;
    ''');
    old.close();

    final migrated = SartiDatabase.open(path, key);
    expect(migrated.raw.userVersion, 3);
    expect(
      migrated.raw.select('SELECT title FROM private_events').single['title'],
      'Private swimming lesson',
    );
    expect(
      migrated.raw
          .select('SELECT calendar_resource_id FROM households')
          .single['calendar_resource_id'],
      'calendar',
    );
    migrated.close();
    expect(
      () => SartiDatabase.open(path, Uint8List.fromList(List.filled(32, 9))),
      throwsA(anything),
    );
  });

  test('encrypted offline edits sync idempotently and produce resolvable conflicts', () async {
    final sodium = await SodiumInit.init();
    final firstDb = SartiDatabase.open(':memory:', Uint8List(32));
    final secondDb = SartiDatabase.open(
      ':memory:',
      Uint8List.fromList(List.filled(32, 1)),
    );
    addTearDown(firstDb.close);
    addTearDown(secondDb.close);
    final firstDevice = newId();
    final secondDevice = newId();
    final first = CalendarRepository(firstDb, deviceId: firstDevice);
    final family = first.createFamily(name: 'Family', ownerName: 'Parent A');
    secondDb.raw.execute(
      'INSERT INTO households(id, display_name, created_at, calendar_resource_id) VALUES (?, ?, ?, ?)',
      [
        family.householdId,
        family.name,
        DateTime.now().toUtc().toIso8601String(),
        family.calendarResourceId,
      ],
    );
    secondDb.raw.execute('INSERT INTO guardians VALUES (?, ?, ?)', [
      newId(),
      family.householdId,
      'Parent B',
    ]);
    final key = sodium.randombytes.buf(32);
    firstDb.setResourceKey(family.calendarResourceId, 1, key);
    secondDb.setResourceKey(family.calendarResourceId, 1, key);
    final eventId = newId();
    CalendarEvent version(String title) => CalendarEvent(
      id: eventId,
      householdId: family.householdId,
      calendarResourceId: family.calendarResourceId,
      title: title,
      localStart: DateTime(2026, 10, 13, 17),
      timezone: 'America/Vancouver',
      durationMinutes: 60,
      childIds: const [],
      reminderMinutes: const [30],
      revision: 1,
      updatedAt: DateTime.now().toUtc(),
    );
    first.saveEvent(version('Swimming with coach A'));
    final second = CalendarRepository(secondDb, deviceId: secondDevice);
    second.saveEvent(version('Swimming with coach B'));
    final relay = _MemoryRelay();
    SyncEngine engine(
      SartiDatabase database,
      CalendarRepository repository,
      String device,
    ) => SyncEngine(
      database: database,
      repository: repository,
      crypto: ResourceCrypto(sodium),
      sodium: sodium,
      relay: relay,
      deviceId: device,
    );

    final firstReport = await engine(
      firstDb,
      first,
      firstDevice,
    ).synchronize(family.householdId);
    final secondReport = await engine(
      secondDb,
      second,
      secondDevice,
    ).synchronize(family.householdId);
    expect(firstReport.uploaded, 2);
    expect(secondReport.conflicts, 1);
    expect(second.openConflicts(), hasLength(1));
    second.resolveConflict(second.openConflicts().single.id, useRemote: true);
    expect(second.openConflicts(), isEmpty);
    expect(second.load()!.events.single.title, 'Swimming with coach A');

    final retry = await engine(
      firstDb,
      first,
      firstDevice,
    ).synchronize(family.householdId);
    expect(retry.uploaded, 0);
    expect(
      relay.operations.map((item) => item.operationId).toSet(),
      hasLength(relay.operations.length),
    );

    final unauthorizedDb = SartiDatabase.open(
      ':memory:',
      Uint8List.fromList(List.filled(32, 2)),
    );
    addTearDown(unauthorizedDb.close);
    unauthorizedDb.raw.execute(
      'INSERT INTO households(id, display_name, created_at, calendar_resource_id) VALUES (?, ?, ?, ?)',
      [
        family.householdId,
        family.name,
        DateTime.now().toUtc().toIso8601String(),
        family.calendarResourceId,
      ],
    );
    final unauthorizedRepository = CalendarRepository(
      unauthorizedDb,
      deviceId: newId(),
    );
    await expectLater(
      engine(
        unauthorizedDb,
        unauthorizedRepository,
        unauthorizedRepository.deviceId,
      ).synchronize(family.householdId),
      throwsStateError,
    );
  });
}

class _MemoryRelay implements EncryptedRelay {
  final List<RelayEnvelope> operations = [];

  @override
  Future<void> upload(RelayEnvelope envelope) async {
    if (operations.any((item) => item.operationId == envelope.operationId)) {
      return;
    }
    operations.add(
      RelayEnvelope(
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

  @override
  Future<RelayPage> download(String familyId, int cursor) async {
    final page = operations
        .where(
          (item) => item.familyId == familyId && item.serverSequence > cursor,
        )
        .toList();
    return RelayPage(page, page.isEmpty ? cursor : page.last.serverSequence);
  }
}
