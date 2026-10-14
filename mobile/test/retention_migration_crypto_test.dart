import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/core/ids.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/features/calendar/domain/calendar_event.dart';
import 'package:timezone/data/latest.dart' as zones;

import 'support/child_sync_fixture.dart';

void main() {
  setUpAll(zones.initializeTimeZones);
  test('RETENTION-MIG-001 encrypted v7 upgrade preserves event and pending envelopes', () {
    final dir = Directory.systemTemp.createTempSync(
      'sarti-retention-migration-',
    );
    final key = Uint8List.fromList(List.generate(32, (i) => i + 1));
    final path = '${dir.path}/fixture.db';
    var store = SartiDatabase.open(path, key);
    final device = newId();
    final repository = CalendarRepository(store, deviceId: device);
    final family = repository.createFamily();
    final original = CalendarEvent(
      id: newId(),
      householdId: family.householdId,
      calendarResourceId: family.calendarResourceId,
      title: 'Preserved pending event',
      localStart: DateTime.utc(2026, 9, 1),
      timezone: 'Etc/UTC',
      durationMinutes: 60,
      childIds: [],
      revision: 1,
      updatedAt: DateTime.utc(2026),
    );
    repository.saveEvent(original);
    store.raw.execute(
      "UPDATE outbox SET envelope_json='synthetic-exact-retry' WHERE kind='event_upserted'",
    );
    store.raw.execute(
      'DROP TABLE retention_conflicts; DROP TABLE calendar_deletions; ALTER TABLE event_versions DROP COLUMN retention_keep_vector; PRAGMA user_version=7',
    );
    store.close();
    try {
      store = SartiDatabase.open(path, key);
      expect(store.raw.userVersion, 8);
      expect(
        CalendarRepository(store, deviceId: device).load()!.events.single.title,
        original.title,
      );
      expect(
        store.raw
            .select(
              "SELECT envelope_json FROM outbox WHERE kind='event_upserted'",
            )
            .single['envelope_json'],
        'synthetic-exact-retry',
      );
      expect(store.raw.select('SELECT * FROM calendar_deletions'), isEmpty);
      store.close();
      expect(() => SartiDatabase.open(path, Uint8List(32)), throwsA(anything));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
  test('RETENTION-CRYPTO-001 offline deletion reconnects as ciphertext and converges', () async {
    final now = DateTime.utc(2026, 10, 13);
    final fixture = ChildSyncFixture(await SodiumInit.init());
    try {
      final old = CalendarEvent(
        id: newId(),
        householdId: fixture.familyId,
        calendarResourceId: fixture.calendarId,
        title: 'Private retention fixture',
        localStart: DateTime.utc(2026, 9, 1),
        timezone: 'Etc/UTC',
        durationMinutes: 60,
        childIds: [],
        revision: 1,
        updatedAt: now,
      );
      fixture.a.repository.saveEvent(old);
      await fixture.a.sync();
      await fixture.b.sync();
      fixture.a.repository.cacheRetentionPolicy({
        'period': 'week',
        'revision': 0,
        'enabled': true,
        'can_manage': true,
      });
      fixture.offline = true;
      expect(fixture.a.repository.sweepRetention(now, canAdminister: true), [
        old.id,
      ]);
      expect(fixture.b.repository.load()!.events, hasLength(1));
      fixture.offline = false;
      await fixture.a.sync();
      await fixture.b.sync();
      expect(fixture.b.repository.load()!.events, isEmpty);
      expect(
        fixture.b.database.raw.select('SELECT * FROM calendar_deletions'),
        hasLength(1),
      );
      final deletion = fixture.operations.last;
      expect(
        String.fromCharCodes(deletion.ciphertext),
        isNot(contains('Private retention fixture')),
      );
      expect((await fixture.b.sync()).applied, 0);
    } finally {
      fixture.close();
    }
  });
}
