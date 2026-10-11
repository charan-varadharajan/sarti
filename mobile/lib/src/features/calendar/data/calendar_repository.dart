import 'dart:convert';

import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/core/ids.dart';
import 'package:sarti_mobile/src/features/calendar/domain/calendar_event.dart';
import 'package:sarti_mobile/src/features/sync/version_vector.dart';

class ChildProfile {
  const ChildProfile({
    required this.id,
    required this.name,
    required this.colorArgb,
  });

  final String id;
  final String name;
  final int colorArgb;
}

class GuardianProfile {
  const GuardianProfile({required this.id, required this.name});

  final String id;
  final String name;
}

class CalendarConflict {
  const CalendarConflict({
    required this.id,
    required this.local,
    required this.remote,
  });

  final String id;
  final CalendarEvent local;
  final CalendarEvent remote;
}

class FamilyCalendar {
  const FamilyCalendar({
    required this.householdId,
    required this.name,
    required this.calendarResourceId,
    required this.children,
    required this.guardians,
    required this.events,
    required this.openConflicts,
  });

  final String householdId;
  final String name;
  final String calendarResourceId;
  final List<ChildProfile> children;
  final List<GuardianProfile> guardians;
  final List<CalendarEvent> events;
  final int openConflicts;
}

enum RemoteApplyResult { applied, duplicate, conflict, stale }

class CalendarRepository {
  CalendarRepository(this.database, {required this.deviceId});

  final SartiDatabase database;
  final String deviceId;

  FamilyCalendar? load() {
    final households = database.raw.select('SELECT * FROM households LIMIT 1');
    if (households.isEmpty) return null;
    final household = households.first;
    final householdId = household['id'] as String;
    final children = database.raw
        .select(
          'SELECT * FROM children WHERE household_id = ? ORDER BY display_name',
          [householdId],
        )
        .map(
          (row) => ChildProfile(
            id: row['id'] as String,
            name: row['display_name'] as String,
            colorArgb: row['color_argb'] as int,
          ),
        )
        .toList();
    final guardians = database.raw
        .select(
          'SELECT * FROM guardians WHERE household_id = ? ORDER BY display_name',
          [householdId],
        )
        .map(
          (row) => GuardianProfile(
            id: row['id'] as String,
            name: row['display_name'] as String,
          ),
        )
        .toList();
    final events = database.raw
        .select(
          'SELECT * FROM events WHERE household_id = ? AND deleted = 0 ORDER BY local_start',
          [householdId],
        )
        .map(_eventFromRow)
        .toList();
    final calendarResource = household['calendar_resource_id'] as String?;
    final conflicts =
        database.raw
                .select(
                  "SELECT count(*) AS total FROM conflicts WHERE status = 'open'",
                )
                .first['total']
            as int;
    return FamilyCalendar(
      householdId: householdId,
      name: household['display_name'] as String,
      calendarResourceId: calendarResource ?? householdId,
      children: children,
      guardians: guardians,
      events: events,
      openConflicts: conflicts,
    );
  }

  FamilyCalendar createFamily({
    String name = 'My family',
    String ownerName = 'Me',
  }) {
    final householdId = newId();
    final calendarResourceId = newId();
    final guardianId = newId();
    final operationId = newId();
    final now = DateTime.now().toUtc().toIso8601String();
    database.transaction(() {
      database.raw.execute(
        'INSERT INTO households(id, display_name, created_at, calendar_resource_id) VALUES (?, ?, ?, ?)',
        [householdId, name, now, calendarResourceId],
      );
      database.raw.execute('INSERT INTO guardians VALUES (?, ?, ?)', [
        guardianId,
        householdId,
        ownerName,
      ]);
      database.raw.execute(
        'INSERT INTO outbox(operation_id, family_id, resource_id, kind, payload_json, vector_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          operationId,
          householdId,
          calendarResourceId,
          'family_created',
          jsonEncode({'householdId': householdId}),
          jsonEncode({deviceId: 1}),
          now,
        ],
      );
    });
    return load()!;
  }

  ChildProfile addChild(String name, int colorArgb) {
    final family = load() ?? (throw StateError('Create a family first.'));
    final child = ChildProfile(
      id: newId(),
      name: name.trim(),
      colorArgb: colorArgb,
    );
    if (child.name.isEmpty) throw ArgumentError.value(name, 'name');
    database.raw.execute('INSERT INTO children VALUES (?, ?, ?, ?)', [
      child.id,
      family.householdId,
      child.name,
      colorArgb,
    ]);
    return child;
  }

  void saveEvent(CalendarEvent event) {
    if (event.title.trim().isEmpty || event.durationMinutes <= 0) {
      throw ArgumentError('Event title and duration are required.');
    }
    final operationId = newId();
    final vector = _nextVector(event.id);
    database.transaction(() {
      database.raw.execute(
        '''INSERT INTO events(
          id, household_id, calendar_resource_id, title, notes, local_start,
          timezone, duration_minutes, status, recurrence_json,
          pickup_guardian_id, dropoff_guardian_id, revision, updated_at, deleted
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          title=excluded.title, notes=excluded.notes,
          local_start=excluded.local_start, timezone=excluded.timezone,
          duration_minutes=excluded.duration_minutes, status=excluded.status,
          recurrence_json=excluded.recurrence_json,
          pickup_guardian_id=excluded.pickup_guardian_id,
          dropoff_guardian_id=excluded.dropoff_guardian_id,
          revision=excluded.revision, updated_at=excluded.updated_at,
          deleted=excluded.deleted''',
        [
          event.id,
          event.householdId,
          event.calendarResourceId,
          event.title.trim(),
          event.notes,
          event.localStart.toIso8601String(),
          event.timezone,
          event.durationMinutes,
          event.status.name,
          event.recurrence == null
              ? null
              : jsonEncode(event.recurrence!.toJson()),
          event.pickupGuardianId,
          event.dropoffGuardianId,
          event.revision,
          event.updatedAt.toUtc().toIso8601String(),
          event.deleted ? 1 : 0,
        ],
      );
      database.raw.execute('DELETE FROM event_children WHERE event_id = ?', [
        event.id,
      ]);
      for (final childId in event.childIds) {
        database.raw.execute('INSERT INTO event_children VALUES (?, ?)', [
          event.id,
          childId,
        ]);
      }
      database.raw.execute('DELETE FROM reminders WHERE event_id = ?', [
        event.id,
      ]);
      for (final minutes in event.reminderMinutes) {
        database.raw.execute('INSERT INTO reminders VALUES (?, ?)', [
          event.id,
          minutes,
        ]);
      }
      database.raw.execute(
        'INSERT OR REPLACE INTO event_versions(event_id, vector_json) VALUES (?, ?)',
        [event.id, jsonEncode(vector)],
      );
      database.raw.execute(
        'INSERT INTO outbox(operation_id, family_id, resource_id, kind, payload_json, vector_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          operationId,
          event.householdId,
          event.calendarResourceId,
          event.deleted ? 'event_deleted' : 'event_upserted',
          event.encode(),
          jsonEncode(vector),
          DateTime.now().toUtc().toIso8601String(),
        ],
      );
    });
  }

  RemoteApplyResult applyRemote({
    required String operationId,
    required CalendarEvent event,
    required Map<String, int> vector,
  }) {
    if (database.raw.select(
      'SELECT 1 FROM applied_operations WHERE operation_id = ?',
      [operationId],
    ).isNotEmpty) {
      return RemoteApplyResult.duplicate;
    }
    final localRows = database.raw.select(
      'SELECT operation_id, payload_json, vector_json FROM outbox WHERE resource_id = ? ORDER BY created_at DESC',
      [event.calendarResourceId],
    );
    final matching = localRows.where((row) {
      final payload =
          jsonDecode(row['payload_json'] as String) as Map<String, dynamic>;
      return payload['id'] == event.id;
    }).firstOrNull;
    if (matching != null) {
      final localVector = Map<String, int>.from(
        jsonDecode(matching['vector_json'] as String) as Map,
      );
      final relation = compareVectors(localVector, vector);
      if (relation == VectorRelation.concurrent) {
        database.transaction(() {
          database.raw.execute(
            'INSERT OR IGNORE INTO conflicts(id, resource_id, local_operation_id, remote_operation_id, local_payload_json, remote_payload_json, created_at, local_vector_json, remote_vector_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
              newId(),
              event.calendarResourceId,
              matching['operation_id'],
              operationId,
              matching['payload_json'],
              event.encode(),
              DateTime.now().toUtc().toIso8601String(),
              matching['vector_json'],
              jsonEncode(vector),
            ],
          );
          database.raw.execute('INSERT INTO applied_operations VALUES (?, ?)', [
            operationId,
            DateTime.now().toUtc().toIso8601String(),
          ]);
        });
        return RemoteApplyResult.conflict;
      }
      if (relation == VectorRelation.after ||
          relation == VectorRelation.equal) {
        return RemoteApplyResult.stale;
      }
    }
    _saveRemote(event, operationId, vector);
    return RemoteApplyResult.applied;
  }

  List<CalendarConflict> openConflicts() => database.raw
      .select(
        "SELECT * FROM conflicts WHERE status = 'open' ORDER BY created_at",
      )
      .map(
        (row) => CalendarConflict(
          id: row['id'] as String,
          local: CalendarEvent.fromJson(
            Map<String, Object?>.from(
              jsonDecode(row['local_payload_json'] as String) as Map,
            ),
          ),
          remote: CalendarEvent.fromJson(
            Map<String, Object?>.from(
              jsonDecode(row['remote_payload_json'] as String) as Map,
            ),
          ),
        ),
      )
      .toList();

  void resolveConflict(String conflictId, {required bool useRemote}) {
    final rows = database.raw.select(
      "SELECT * FROM conflicts WHERE id = ? AND status = 'open'",
      [conflictId],
    );
    if (rows.isEmpty) throw StateError('Conflict is no longer open.');
    final row = rows.first;
    final selected = CalendarEvent.fromJson(
      Map<String, Object?>.from(
        jsonDecode(
          row[useRemote ? 'remote_payload_json' : 'local_payload_json']
              as String,
        ) as Map,
      ),
    );
    final next = selected.copyWith(
      revision: selected.revision + 1,
      updatedAt: DateTime.now().toUtc(),
    );
    final localVector = row['local_vector_json'] == null
        ? <String, int>{}
        : Map<String, int>.from(
            jsonDecode(row['local_vector_json'] as String) as Map,
          );
    final remoteVector = row['remote_vector_json'] == null
        ? <String, int>{}
        : Map<String, int>.from(
            jsonDecode(row['remote_vector_json'] as String) as Map,
          );
    final resolvedVector = mergeVectors(localVector, remoteVector);
    resolvedVector[deviceId] = (resolvedVector[deviceId] ?? 0) + 1;
    database.transaction(() {
      database.raw.execute(
        "UPDATE conflicts SET status = 'resolved' WHERE id = ? AND status = 'open'",
        [conflictId],
      );
      _saveEventRows(next, vector: resolvedVector);
      database.raw.execute(
        'INSERT INTO outbox(operation_id, family_id, resource_id, kind, payload_json, vector_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          newId(),
          next.householdId,
          next.calendarResourceId,
          'conflict_resolved',
          next.encode(),
          jsonEncode(resolvedVector),
          DateTime.now().toUtc().toIso8601String(),
        ],
      );
    });
  }

  void _saveRemote(
    CalendarEvent event,
    String operationId,
    Map<String, int> vector,
  ) {
    database.transaction(() {
      _saveEventRows(event, vector: vector);
      database.raw.execute('INSERT INTO applied_operations VALUES (?, ?)', [
        operationId,
        DateTime.now().toUtc().toIso8601String(),
      ]);
    });
  }

  void _saveEventRows(CalendarEvent event, {Map<String, int>? vector}) {
    database.raw.execute(
      'INSERT OR REPLACE INTO events VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        event.id,
        event.householdId,
        event.calendarResourceId,
        event.title,
        event.notes,
        event.localStart.toIso8601String(),
        event.timezone,
        event.durationMinutes,
        event.status.name,
        event.recurrence == null
            ? null
            : jsonEncode(event.recurrence!.toJson()),
        event.pickupGuardianId,
        event.dropoffGuardianId,
        event.revision,
        event.updatedAt.toUtc().toIso8601String(),
        event.deleted ? 1 : 0,
      ],
    );
    database.raw.execute('DELETE FROM event_children WHERE event_id = ?', [
      event.id,
    ]);
    for (final childId in event.childIds) {
      database.raw.execute('INSERT INTO event_children VALUES (?, ?)', [
        event.id,
        childId,
      ]);
    }
    database.raw.execute('DELETE FROM reminders WHERE event_id = ?', [
      event.id,
    ]);
    for (final minutes in event.reminderMinutes) {
      database.raw.execute('INSERT INTO reminders VALUES (?, ?)', [
        event.id,
        minutes,
      ]);
    }
    if (vector != null) {
      database.raw.execute(
        'INSERT OR REPLACE INTO event_versions(event_id, vector_json) VALUES (?, ?)',
        [event.id, jsonEncode(vector)],
      );
    }
  }

  Map<String, int> _nextVector(String eventId) {
    final rows = database.raw.select(
      'SELECT vector_json FROM event_versions WHERE event_id = ?',
      [eventId],
    );
    final vector = rows.isEmpty
        ? <String, int>{}
        : Map<String, int>.from(
            jsonDecode(rows.first['vector_json'] as String) as Map,
          );
    vector[deviceId] = (vector[deviceId] ?? 0) + 1;
    return vector;
  }

  CalendarEvent _eventFromRow(dynamic row) {
    final eventId = row['id'] as String;
    final childIds = database.raw
        .select('SELECT child_id FROM event_children WHERE event_id = ?', [
          eventId,
        ])
        .map((value) => value['child_id'] as String)
        .toList();
    final reminders = database.raw
        .select('SELECT minutes_before FROM reminders WHERE event_id = ?', [
          eventId,
        ])
        .map((value) => value['minutes_before'] as int)
        .toList();
    return CalendarEvent(
      id: eventId,
      householdId: row['household_id'] as String,
      calendarResourceId: row['calendar_resource_id'] as String,
      title: row['title'] as String,
      notes: row['notes'] as String?,
      localStart: DateTime.parse(row['local_start'] as String),
      timezone: row['timezone'] as String,
      durationMinutes: row['duration_minutes'] as int,
      status: EventStatus.values.byName(row['status'] as String),
      recurrence: row['recurrence_json'] == null
          ? null
          : RecurrenceRule.fromJson(
              Map<String, Object?>.from(
                jsonDecode(row['recurrence_json'] as String) as Map,
              ),
            ),
      childIds: childIds,
      pickupGuardianId: row['pickup_guardian_id'] as String?,
      dropoffGuardianId: row['dropoff_guardian_id'] as String?,
      reminderMinutes: reminders,
      revision: row['revision'] as int,
      updatedAt: DateTime.parse(row['updated_at'] as String),
      deleted: (row['deleted'] as int) == 1,
    );
  }
}
