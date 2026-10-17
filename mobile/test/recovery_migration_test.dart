import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/core/ids.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/features/calendar/domain/calendar_event.dart';
import 'package:timezone/data/latest.dart' as zones;

void main() {
  setUpAll(zones.initializeTimeZones);
  test('RECOVERY-MIG-001 v8 upgrade preserves keys/vectors/retries; legacy pause stays blocked', () {
    final folder = Directory.systemTemp.createTempSync(
      'sarti-recovery-migration-',
    );
    final key = Uint8List.fromList(List.generate(32, (i) => i + 7));
    final path = '${folder.path}/source.db';
    var db = SartiDatabase.open(path, key);
    final device = newId();
    final repo = CalendarRepository(db, deviceId: device);
    final family = repo.createFamily();
    repo.saveEvent(
      CalendarEvent(
        id: newId(),
        householdId: family.householdId,
        calendarResourceId: family.calendarResourceId,
        title: 'Existing encrypted history',
        localStart: DateTime.utc(2026, 12, 1),
        timezone: 'Etc/UTC',
        durationMinutes: 60,
        childIds: [],
        revision: 1,
        updatedAt: DateTime.utc(2026, 10, 13),
      ),
    );
    db.setResourceKey(family.calendarResourceId, 1, key);
    db.raw.execute(
      "UPDATE outbox SET envelope_json='exact-old-retry' WHERE kind='event_upserted'",
    );
    db.raw.execute(
      'DROP TABLE recovery_intents; DROP TABLE recovery_state; PRAGMA user_version=8',
    );
    db.close();
    try {
      db = SartiDatabase.open(path, key);
      expect(db.raw.userVersion, SartiDatabase.schemaVersion);
      expect(CalendarRepository(db, deviceId: device).recoveryPending, isFalse);
      expect(db.resourceKey(family.calendarResourceId, 1), key);
      expect(db.raw.select('SELECT * FROM event_versions'), hasLength(1));
      expect(
        db.raw
            .select(
              "SELECT envelope_json FROM outbox WHERE kind='event_upserted'",
            )
            .single['envelope_json'],
        'exact-old-retry',
      );
      db.raw.execute(
        "INSERT INTO app_preferences VALUES ('retention-recovery-pending','true')",
      );
      db.raw.execute(
        'DROP TABLE recovery_intents; DROP TABLE recovery_state; PRAGMA user_version=8',
      );
      db.close();
      db = SartiDatabase.open(path, key);
      final recovered = CalendarRepository(db, deviceId: device);
      expect(recovered.recoveryState!['phase'], 'blocked');
      expect(
        recovered.load()!.events.single.title,
        'Existing encrypted history',
      );
      db.close();
      expect(() => SartiDatabase.open(path, Uint8List(32)), throwsA(anything));
    } finally {
      folder.deleteSync(recursive: true);
    }
  });
}
