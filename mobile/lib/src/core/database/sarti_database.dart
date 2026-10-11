import 'dart:convert';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

class SartiDatabase {
  SartiDatabase._(this.raw);

  static const schemaVersion = 2;

  final Database raw;

  static SartiDatabase open(String path, Uint8List key) {
    if (key.length != 32) {
      throw ArgumentError.value(key.length, 'key.length', 'must be 32');
    }
    final database = sqlite3.open(path);
    try {
      final hexKey = key.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
      database.execute('PRAGMA key = "x\'$hexKey\'"');
      final cipher = database.select('PRAGMA cipher_version');
      if (cipher.isEmpty || cipher.first.values.first.toString().isEmpty) {
        throw StateError('SQLCipher is unavailable.');
      }
      database.execute('PRAGMA foreign_keys = ON');
      database.select('SELECT count(*) FROM sqlite_master');
      final result = SartiDatabase._(database);
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
    return rows.isEmpty ? null : base64Url.decode(rows.first['key_base64'] as String);
  }

  void close() => raw.close();
}
