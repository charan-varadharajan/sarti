import 'dart:convert';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

class SartiDatabase {
  SartiDatabase._(this.raw, this.path);

  static const schemaVersion = 10;

  final Database raw;
  final String path;

  static SartiDatabase open(String path, Uint8List key) {
    if (key.length != 32) {
      throw ArgumentError.value(key.length, 'key.length', 'must be 32');
    }
    final database = sqlite3.open(path);
    try {
      final hexKey = key
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();
      database.execute('PRAGMA key = "x\'$hexKey\'"');
      final cipher = database.select('PRAGMA cipher_version');
      if (cipher.isEmpty || cipher.first.values.first.toString().isEmpty) {
        throw StateError('SQLCipher is unavailable.');
      }
      database.execute('PRAGMA foreign_keys = ON');
      database.execute('PRAGMA secure_delete = ON');
      database.select('SELECT count(*) FROM sqlite_master');
      final result = SartiDatabase._(database, path);
      result._migrate();
      return result;
    } catch (_) {
      database.close();
      rethrow;
    }
  }

  void _migrate() {
    final current = raw.userVersion;
    if (current > schemaVersion) {
      throw StateError('Local database schema is newer than this app.');
    }
    if (current < 1) {
      raw.execute('BEGIN IMMEDIATE');
      try {
        raw.execute('''
          CREATE TABLE households (
            id TEXT PRIMARY KEY,
            display_name TEXT NOT NULL,
            created_at TEXT NOT NULL
          ) STRICT;
          CREATE TABLE guardians (
            id TEXT PRIMARY KEY,
            household_id TEXT NOT NULL REFERENCES households(id) ON DELETE CASCADE,
            display_name TEXT NOT NULL
          ) STRICT;
          CREATE TABLE children (
            id TEXT PRIMARY KEY,
            household_id TEXT NOT NULL REFERENCES households(id) ON DELETE CASCADE,
            display_name TEXT NOT NULL,
            color_argb INTEGER NOT NULL
          ) STRICT;
          CREATE TABLE events (
            id TEXT PRIMARY KEY,
            household_id TEXT NOT NULL REFERENCES households(id) ON DELETE CASCADE,
            calendar_resource_id TEXT NOT NULL,
            title TEXT NOT NULL,
            notes TEXT,
            local_start TEXT NOT NULL,
            timezone TEXT NOT NULL,
            duration_minutes INTEGER NOT NULL CHECK(duration_minutes > 0),
            status TEXT NOT NULL CHECK(status IN ('scheduled', 'cancelled')),
            recurrence_json TEXT,
            pickup_guardian_id TEXT REFERENCES guardians(id),
            dropoff_guardian_id TEXT REFERENCES guardians(id),
            revision INTEGER NOT NULL CHECK(revision > 0),
            updated_at TEXT NOT NULL,
            deleted INTEGER NOT NULL DEFAULT 0 CHECK(deleted IN (0, 1))
          ) STRICT;
          CREATE INDEX ix_events_household_start
            ON events(household_id, local_start) WHERE deleted = 0;
          CREATE TABLE event_children (
            event_id TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
            child_id TEXT NOT NULL REFERENCES children(id) ON DELETE CASCADE,
            PRIMARY KEY(event_id, child_id)
          ) STRICT;
          CREATE TABLE reminders (
            event_id TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
            minutes_before INTEGER NOT NULL CHECK(minutes_before >= 0),
            PRIMARY KEY(event_id, minutes_before)
          ) STRICT;
        ''');
        raw.userVersion = 1;
        raw.execute('COMMIT');
      } catch (_) {
        raw.execute('ROLLBACK');
        rethrow;
      }
    }
    if (raw.userVersion < 2) {
      raw.execute('BEGIN IMMEDIATE');
      try {
        raw.execute('''
          CREATE TABLE outbox (
            operation_id TEXT PRIMARY KEY,
            family_id TEXT NOT NULL,
            resource_id TEXT NOT NULL,
            kind TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            vector_json TEXT NOT NULL,
            state TEXT NOT NULL DEFAULT 'pending'
              CHECK(state IN ('pending', 'uploaded')),
            created_at TEXT NOT NULL
          ) STRICT;
          CREATE INDEX ix_outbox_pending ON outbox(created_at) WHERE state = 'pending';
          CREATE TABLE applied_operations (
            operation_id TEXT PRIMARY KEY,
            applied_at TEXT NOT NULL
          ) STRICT;
          CREATE TABLE conflicts (
            id TEXT PRIMARY KEY,
            resource_id TEXT NOT NULL,
            local_operation_id TEXT NOT NULL,
            remote_operation_id TEXT NOT NULL,
            local_payload_json TEXT NOT NULL,
            remote_payload_json TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'open'
              CHECK(status IN ('open', 'resolved')),
            created_at TEXT NOT NULL,
            UNIQUE(local_operation_id, remote_operation_id)
          ) STRICT;
          CREATE TABLE resource_keys (
            resource_id TEXT NOT NULL,
            key_epoch INTEGER NOT NULL CHECK(key_epoch > 0),
            key_base64 TEXT NOT NULL,
            PRIMARY KEY(resource_id, key_epoch)
          ) STRICT;
          CREATE TABLE sync_state (
            family_id TEXT PRIMARY KEY,
            server_cursor INTEGER NOT NULL DEFAULT 0 CHECK(server_cursor >= 0)
          ) STRICT;
        ''');
        raw.userVersion = 2;
        raw.execute('COMMIT');
      } catch (_) {
        raw.execute('ROLLBACK');
        rethrow;
      }
    }
    if (raw.userVersion < 3) {
      raw.execute('BEGIN IMMEDIATE');
      try {
        raw.execute('''
          ALTER TABLE households ADD COLUMN calendar_resource_id TEXT;
          UPDATE households SET calendar_resource_id = COALESCE(
            (SELECT resource_id FROM outbox
             WHERE outbox.family_id = households.id
               AND outbox.kind = 'family_created'
             ORDER BY created_at LIMIT 1),
            id
          );
          ALTER TABLE sync_state ADD COLUMN next_device_sequence INTEGER NOT NULL DEFAULT 1
            CHECK(next_device_sequence > 0);
          ALTER TABLE conflicts ADD COLUMN local_vector_json TEXT;
          ALTER TABLE conflicts ADD COLUMN remote_vector_json TEXT;
          CREATE TABLE event_versions (
            event_id TEXT PRIMARY KEY REFERENCES events(id) ON DELETE CASCADE,
            vector_json TEXT NOT NULL
          ) STRICT;
        ''');
        raw.userVersion = 3;
        raw.execute('COMMIT');
      } catch (_) {
        raw.execute('ROLLBACK');
        rethrow;
      }
    }
    if (raw.userVersion < 4) {
      raw.execute('BEGIN IMMEDIATE');
      try {
        raw.execute('''
          ALTER TABLE children ADD COLUMN cloud_alias TEXT;
          UPDATE children
             SET cloud_alias = 'child-' || lower(hex(randomblob(8)))
           WHERE cloud_alias IS NULL;
          CREATE UNIQUE INDEX uq_children_household_cloud_alias
            ON children(household_id, cloud_alias COLLATE NOCASE)
            WHERE cloud_alias IS NOT NULL;
        ''');
        raw.userVersion = 4;
        raw.execute('COMMIT');
      } catch (_) {
        raw.execute('ROLLBACK');
        rethrow;
      }
    }
    if (raw.userVersion < 5) {
      raw.execute('BEGIN IMMEDIATE');
      try {
        raw.execute('''
          CREATE TABLE app_preferences (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          ) STRICT;
        ''');
        raw.userVersion = 5;
        raw.execute('COMMIT');
      } catch (_) {
        raw.execute('ROLLBACK');
        rethrow;
      }
    }
    if (raw.userVersion < 6) {
      transaction(() {
        raw.execute('''
          ALTER TABLE outbox ADD COLUMN envelope_json TEXT;
          ALTER TABLE children ADD COLUMN is_placeholder INTEGER NOT NULL DEFAULT 0
            CHECK(is_placeholder IN (0, 1));
          CREATE TABLE resource_catalog (
            resource_id TEXT PRIMARY KEY,
            family_id TEXT NOT NULL,
            kind TEXT NOT NULL,
            key_epoch INTEGER NOT NULL CHECK(key_epoch > 0)
          ) STRICT;
          CREATE TABLE child_sync (
            child_id TEXT PRIMARY KEY REFERENCES children(id) ON DELETE CASCADE,
            key_epoch INTEGER NOT NULL CHECK(key_epoch >= 0),
            share_with_calendar_guardians INTEGER NOT NULL DEFAULT 0
              CHECK(share_with_calendar_guardians IN (0, 1))
          ) STRICT;
        ''');
        raw.userVersion = 6;
      });
    }
    if (raw.userVersion < 7) {
      transaction(() {
        raw.execute('''
          CREATE TABLE child_profile_versions (
            child_id TEXT PRIMARY KEY REFERENCES children(id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
            vector_json TEXT NOT NULL
          ) STRICT;
          CREATE TABLE participant_profiles (
            id TEXT PRIMARY KEY,
            household_id TEXT NOT NULL REFERENCES households(id) ON DELETE CASCADE,
            kind TEXT NOT NULL CHECK(kind IN ('adult', 'pet')),
            display_name TEXT NOT NULL,
            color_argb INTEGER NOT NULL,
            adult_id TEXT,
            vector_json TEXT NOT NULL DEFAULT '{}'
          ) STRICT;
          CREATE TABLE event_participants (
            event_id TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
            profile_id TEXT NOT NULL,
            kind TEXT NOT NULL CHECK(kind IN ('adult', 'pet')),
            PRIMARY KEY(event_id, profile_id)
          ) STRICT;
          CREATE TABLE personal_calendars (
            adult_id TEXT PRIMARY KEY,
            household_id TEXT NOT NULL REFERENCES households(id) ON DELETE CASCADE,
            resource_id TEXT NOT NULL UNIQUE
          ) STRICT;
          CREATE TABLE appointment_shares (
            private_event_id TEXT PRIMARY KEY REFERENCES events(id) ON DELETE CASCADE,
            shared_event_id TEXT NOT NULL UNIQUE,
            shared_vector_json TEXT NOT NULL
          ) STRICT;
        ''');
        raw.userVersion = 7;
      });
    }
    if (raw.userVersion < 8) {
      transaction(() {
        raw.execute(
          '''ALTER TABLE event_versions ADD COLUMN retention_keep_vector TEXT;
        CREATE TABLE calendar_deletions (
          event_id TEXT PRIMARY KEY,
          household_id TEXT NOT NULL REFERENCES households(id) ON DELETE CASCADE,
          resource_id TEXT NOT NULL,
          vector_json TEXT NOT NULL,
          deleted_at TEXT NOT NULL
        ) STRICT;
        CREATE TABLE retention_conflicts (
          event_id TEXT PRIMARY KEY,
          resource_id TEXT NOT NULL,
          deletion_json TEXT NOT NULL,
          event_json TEXT NOT NULL,
          event_vector_json TEXT NOT NULL
        ) STRICT;''',
        );
        raw.userVersion = 8;
      });
    }
    if (raw.userVersion < 9) {
      transaction(() {
        raw.execute(
          '''CREATE TABLE recovery_state (
          family_id TEXT PRIMARY KEY REFERENCES households(id) ON DELETE CASCADE,
          phase TEXT NOT NULL CHECK(phase IN ('snapshot','paused','catching_up','review','ready','blocked')),
          snapshot_at TEXT,
          profile_vector_json TEXT,
          reason TEXT
        ) STRICT;
        CREATE TABLE recovery_intents (
          source_operation_id TEXT PRIMARY KEY,
          family_id TEXT NOT NULL REFERENCES households(id) ON DELETE CASCADE,
          resource_id TEXT NOT NULL,
          kind TEXT NOT NULL,
          payload_json TEXT NOT NULL,
          vector_json TEXT NOT NULL,
          status TEXT NOT NULL CHECK(status IN ('pending','quarantined','queued','done')),
          queued_operation_id TEXT UNIQUE,
          reason TEXT,
          reviewed_payload_json TEXT,
          reviewed_vector_json TEXT
        ) STRICT;
        INSERT INTO recovery_state(family_id,phase,reason)
          SELECT id,'blocked','legacy_missing_history' FROM households
          WHERE EXISTS (SELECT 1 FROM app_preferences WHERE key='retention-recovery-pending');''',
        );
        raw.userVersion = 9;
      });
    }
    if (raw.userVersion < 10) {
      transaction(() {
        // Preserve exact outbox envelopes and per-context cursors. The device
        // counter is initialized by the authenticated engine, never renumbered.
        raw.execute('''
          CREATE TABLE IF NOT EXISTS device_sync_state (
            device_id TEXT PRIMARY KEY,
            next_device_sequence INTEGER NOT NULL CHECK(next_device_sequence > 0)
          ) STRICT;
        ''');
        final fields = raw.select('PRAGMA table_info(personal_calendars)');
        if (fields.any((r) => r['name'] == 'household_id' && r['pk'] == 0)) {
          raw.execute('''
            ALTER TABLE personal_calendars RENAME TO personal_calendars_legacy;
            CREATE TABLE personal_calendars (
              adult_id TEXT NOT NULL,
              household_id TEXT NOT NULL REFERENCES households(id) ON DELETE CASCADE,
              resource_id TEXT NOT NULL UNIQUE,
              PRIMARY KEY(adult_id, household_id)
            ) STRICT;
            INSERT INTO personal_calendars SELECT * FROM personal_calendars_legacy;
            DROP TABLE personal_calendars_legacy;
          ''');
        }
        raw.userVersion = 10;
      });
    }
  }

  void transaction(void Function() action) {
    raw.execute('BEGIN IMMEDIATE');
    try {
      action();
      raw.execute('COMMIT');
    } catch (_) {
      raw.execute('ROLLBACK');
      rethrow;
    }
  }

  void setResourceKey(String resourceId, int epoch, Uint8List key) {
    raw.execute(
      'INSERT OR REPLACE INTO resource_keys(resource_id, key_epoch, key_base64) VALUES (?, ?, ?)',
      [resourceId, epoch, base64UrlEncode(key)],
    );
  }

  Uint8List? resourceKey(String resourceId, int epoch) {
    final rows = raw.select(
      'SELECT key_base64 FROM resource_keys WHERE resource_id = ? AND key_epoch = ?',
      [resourceId, epoch],
    );
    return rows.isEmpty
        ? null
        : base64Url.decode(rows.first['key_base64'] as String);
  }

  void close() => raw.close();
}
