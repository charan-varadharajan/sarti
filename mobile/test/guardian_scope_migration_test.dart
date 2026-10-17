import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sqlite3/sqlite3.dart';

/// Actual pre-v12 SQL shapes; no current-schema downgrade simulation.
void _legacy(String path, Uint8List key, {required bool crossScope}) {
  final db = sqlite3.open(path);
  try {
    final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    db.execute('PRAGMA key="x\'$hex\'"');
    expect(db.select('PRAGMA cipher_version'), isNotEmpty);
    db.execute('PRAGMA foreign_keys=ON');
    db.execute('''
      CREATE TABLE households(id TEXT PRIMARY KEY,display_name TEXT NOT NULL,created_at TEXT NOT NULL,calendar_resource_id TEXT) STRICT;
      CREATE TABLE guardians(id TEXT PRIMARY KEY,household_id TEXT NOT NULL REFERENCES households(id) ON DELETE CASCADE,display_name TEXT NOT NULL) STRICT;
      CREATE TABLE events(
        id TEXT PRIMARY KEY,household_id TEXT NOT NULL REFERENCES households(id) ON DELETE CASCADE,
        calendar_resource_id TEXT NOT NULL,title TEXT NOT NULL,notes TEXT,local_start TEXT NOT NULL,
        timezone TEXT NOT NULL,duration_minutes INTEGER NOT NULL CHECK(duration_minutes>0),
        status TEXT NOT NULL CHECK(status IN ('scheduled','cancelled')),recurrence_json TEXT,
        pickup_guardian_id TEXT REFERENCES guardians(id),dropoff_guardian_id TEXT REFERENCES guardians(id),
        revision INTEGER NOT NULL CHECK(revision>0),updated_at TEXT NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0 CHECK(deleted IN (0,1))
      ) STRICT;
      CREATE INDEX ix_events_household_start ON events(household_id,local_start) WHERE deleted=0;
      CREATE TABLE children(id TEXT PRIMARY KEY,household_id TEXT NOT NULL REFERENCES households(id) ON DELETE CASCADE) STRICT;
      CREATE TABLE event_children(event_id TEXT REFERENCES events(id) ON DELETE CASCADE,child_id TEXT REFERENCES children(id) ON DELETE CASCADE,PRIMARY KEY(event_id,child_id)) STRICT;
      CREATE TABLE reminders(event_id TEXT REFERENCES events(id) ON DELETE CASCADE,minutes_before INTEGER NOT NULL,PRIMARY KEY(event_id,minutes_before)) STRICT;
      CREATE TABLE event_versions(event_id TEXT PRIMARY KEY REFERENCES events(id) ON DELETE CASCADE,vector_json TEXT NOT NULL) STRICT;
      CREATE TABLE resource_keys(resource_id TEXT,key_epoch INTEGER,key_base64 TEXT,PRIMARY KEY(resource_id,key_epoch)) STRICT;
      CREATE TABLE outbox(operation_id TEXT PRIMARY KEY,envelope_json TEXT) STRICT;
      INSERT INTO households VALUES ('a','Synthetic A','2026-10-16','calendar-a'),('b','Synthetic B','2026-10-16','calendar-b');
      INSERT INTO children VALUES ('child-a','a');
    ''');
    db.execute('INSERT INTO guardians VALUES (?,?,?)', [
      'adult',
      crossScope ? 'b' : 'a',
      'Synthetic guardian',
    ]);
    db.execute(
      "INSERT INTO events VALUES ('event-a','a','calendar-a','Encrypted migration canary','Private notes','2026-12-01T09:00:00','Etc/UTC',60,'scheduled',NULL,'adult',NULL,1,'2026-10-16T00:00:00',0)",
    );
    db.execute(
      "INSERT INTO event_children VALUES ('event-a','child-a'); INSERT INTO reminders VALUES ('event-a',30); INSERT INTO event_versions VALUES ('event-a','{\"synthetic-device\":1}'); INSERT INTO resource_keys VALUES ('calendar-a',1,'synthetic exact key'); INSERT INTO outbox VALUES ('operation-a','synthetic exact authenticated bytes'); PRAGMA user_version=11;",
    );
  } finally {
    db.close();
  }
}

void main() {
  for (final crossScope in [false, true]) {
    test(
      'S5-MIGRATE-002 ${crossScope ? 'invalid legacy assignment rolls back without loss' : 'v11 guardian migration preserves encrypted relationships and retries'}',
      () {
        final directory = Directory.systemTemp.createTempSync(
          'sarti-guardian-migration-',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        final path = '${directory.path}/legacy.db';
        final key = Uint8List.fromList(List.generate(32, (i) => i + 1));
        _legacy(path, key, crossScope: crossScope);
        if (crossScope) {
          expect(() => SartiDatabase.open(path, key), throwsStateError);
          final unchanged = sqlite3.open(path);
          try {
            unchanged.execute(
              'PRAGMA key="x\'${key.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}\'"',
            );
            expect(unchanged.userVersion, 11);
            expect(
              unchanged.select('SELECT title FROM events').single['title'],
              'Encrypted migration canary',
            );
            expect(
              unchanged
                  .select('SELECT envelope_json FROM outbox')
                  .single['envelope_json'],
              'synthetic exact authenticated bytes',
            );
          } finally {
            unchanged.close();
          }
        } else {
          final upgraded = SartiDatabase.open(path, key);
          try {
            expect(upgraded.raw.userVersion, SartiDatabase.schemaVersion);
            expect(
              upgraded.raw.select('PRAGMA foreign_keys').single.values.single,
              1,
            );
            expect(
              upgraded.raw.select('SELECT * FROM event_children'),
              hasLength(1),
            );
            expect(
              upgraded.raw.select('SELECT * FROM reminders'),
              hasLength(1),
            );
            expect(
              upgraded.raw
                  .select('SELECT vector_json FROM event_versions')
                  .single['vector_json'],
              '{"synthetic-device":1}',
            );
            expect(
              upgraded.raw
                  .select('SELECT key_base64 FROM resource_keys')
                  .single['key_base64'],
              'synthetic exact key',
            );
            expect(
              upgraded.raw
                  .select('SELECT envelope_json FROM outbox')
                  .single['envelope_json'],
              'synthetic exact authenticated bytes',
            );
            upgraded.raw.execute(
              "INSERT INTO guardians VALUES ('adult','b','Independent B name')",
            );
            expect(
              upgraded.raw.select('SELECT * FROM guardians'),
              hasLength(2),
            );
            expect(upgraded.raw.select('PRAGMA foreign_key_check'), isEmpty);
          } finally {
            upgraded.close();
          }
        }
        expect(
          latin1.decode(File(path).readAsBytesSync()),
          isNot(contains('Encrypted migration canary')),
        );
        expect(
          () => SartiDatabase.open(path, Uint8List(32)),
          throwsA(anything),
        );
      },
    );
  }
}
