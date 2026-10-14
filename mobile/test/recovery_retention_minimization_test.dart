import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/core/ids.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/features/calendar/domain/calendar_event.dart';
import 'package:timezone/data/latest.dart' as zones;

void main() {
  test('RECOVERY-RETENTION-001 expired entry removes completed recovery body, preserving pending intent', () async {
    zones.initializeTimeZones();
    final sodium = await SodiumInit.init();
    final db = SartiDatabase.open(':memory:', sodium.randombytes.buf(32));
    try {
      final repo = CalendarRepository(db, deviceId: newId());
      final family = repo.createFamily();
      final event = CalendarEvent(
        id: newId(),
        householdId: family.householdId,
        calendarResourceId: family.calendarResourceId,
        title: 'Expired recovered appointment',
        localStart: DateTime.utc(2026, 1, 1),
        timezone: 'Etc/UTC',
        durationMinutes: 60,
        childIds: [],
        revision: 1,
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      repo.saveEvent(event);
      db.raw.execute("UPDATE outbox SET state='uploaded'");
      final done = newId(), pending = newId();
      for (final id in [done, pending]) {
        db.raw.execute(
          'INSERT INTO recovery_intents(source_operation_id,family_id,resource_id,kind,payload_json,vector_json,status) VALUES (?,?,?,?,?,?,?)',
          [
            id,
            family.householdId,
            family.calendarResourceId,
            'event_upserted',
            event.encode(),
            jsonEncode({repo.deviceId: 1}),
            id == done ? 'done' : 'quarantined',
          ],
        );
      }
      repo.cacheRetentionPolicy({
        'period': 'week',
        'revision': 1,
        'enabled': true,
        'can_manage': true,
      });
      expect(
        repo.sweepRetention(DateTime.utc(2026, 10, 13), canAdminister: true),
        [event.id],
      );
      expect(
        db.raw
            .select('SELECT source_operation_id FROM recovery_intents')
            .single['source_operation_id'],
        pending,
      );
      expect(db.raw.select('SELECT * FROM events'), isEmpty);
      expect(db.raw.select('SELECT * FROM calendar_deletions'), hasLength(1));
      db.raw.execute("UPDATE recovery_intents SET status='done'");
      repo.reconcileRecoveryIntents();
      expect(db.raw.select('SELECT * FROM recovery_intents'), isEmpty);
    } finally {
      db.close();
    }
  });
}
