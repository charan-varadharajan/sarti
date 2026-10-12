import 'dart:convert';

import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/core/ids.dart';
import 'package:sarti_mobile/src/features/ai/cloud_alias.dart';
import 'package:sarti_mobile/src/features/calendar/domain/calendar_event.dart';
import 'package:sarti_mobile/src/features/sync/version_vector.dart';
import 'package:timezone/timezone.dart' as tz;

class ChildProfile {
  const ChildProfile({
    required this.id,
    required this.name,
    required this.colorArgb,
    required this.cloudAlias,
  });

  final String id;
  final String name;
  final int colorArgb;
  final String cloudAlias;
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

  Map<String, String> get cloudChildAliases => {
    for (final child in children) child.name: child.cloudAlias,
  };
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
          'SELECT * FROM children WHERE household_id = ? AND is_placeholder = 0 ORDER BY display_name',
          [householdId],
        )
        .map(
          (row) => ChildProfile(
            id: row['id'] as String,
            name: row['display_name'] as String,
            colorArgb: row['color_argb'] as int,
            cloudAlias: row['cloud_alias'] as String,
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
    String? familyId,
    String? calendarResourceId,
  }) {
    final householdId = familyId ?? newId();
    final resourceId = calendarResourceId ?? newId();
    final guardianId = newId();
    final operationId = newId();
    final now = DateTime.now().toUtc().toIso8601String();
    database.transaction(() {
      database.raw.execute(
        'INSERT INTO households(id, display_name, created_at, calendar_resource_id) VALUES (?, ?, ?, ?)',
        [householdId, name, now, resourceId],
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
          resourceId,
          'family_created',
          jsonEncode({'householdId': householdId}),
          jsonEncode({deviceId: 1}),
          now,
        ],
      );
    });
    return load()!;
  }

  ChildProfile addChild(
    String name,
    int colorArgb, {
    String? cloudAlias,
    bool shareWithCalendarGuardians = false,
  }) {
    final family = load() ?? (throw StateError('Create a family first.'));
    final childName = name.trim();
    if (childName.isEmpty ||
        childName.length > 120 ||
        colorArgb < 0 ||
        colorArgb > 0xffffffff) {
      throw ArgumentError('Invalid child profile.');
    }
    var alias = CloudAlias.validate(
      cloudAlias?.trim().isNotEmpty == true
          ? cloudAlias!
          : CloudAlias.generate(childName: childName),
      childName: childName,
    );
    while (database.raw.select(
      'SELECT 1 FROM children WHERE household_id = ? AND cloud_alias = ? COLLATE NOCASE',
      [family.householdId, alias],
    ).isNotEmpty) {
      if (cloudAlias?.trim().isNotEmpty == true) {
        throw ArgumentError.value(
          cloudAlias,
          'cloudAlias',
          'This private AI alias is already in use.',
        );
      }
      alias = CloudAlias.generate(childName: childName);
    }
    final child = ChildProfile(
      id: newId(),
      name: childName,
      colorArgb: colorArgb,
      cloudAlias: alias,
    );
    database.transaction(() {
      database.raw.execute(
        'INSERT INTO children(id, household_id, display_name, color_argb, cloud_alias) VALUES (?, ?, ?, ?, ?)',
        [child.id, family.householdId, child.name, colorArgb, child.cloudAlias],
      );
      queueChildProfile(child.id);
      database.raw.execute(
        'INSERT INTO child_sync(child_id, key_epoch, share_with_calendar_guardians) VALUES (?, 0, ?)',
        [child.id, shareWithCalendarGuardians ? 1 : 0],
      );
    });
    return child;
  }

  /// Called inside the caller's transaction for atomic profile/outbox writes.
  void queueChildProfile(String childId) {
    final row = database.raw.select(
      'SELECT * FROM children WHERE id = ? AND is_placeholder = 0',
      [childId],
    ).single;
    database.raw.execute(
      'INSERT INTO outbox(operation_id, family_id, resource_id, kind, payload_json, vector_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        newId(),
        row['household_id'],
        childId,
        'child_created',
        jsonEncode({
          'id': childId,
          'householdId': row['household_id'],
          'name': row['display_name'],
          'colorArgb': row['color_argb'],
          'cloudAlias': row['cloud_alias'],
        }),
        jsonEncode({deviceId: 1}),
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
  }

  RemoteApplyResult applyRemoteChild({
    required String operationId,
    required String familyId,
    required String resourceId,
    required int keyEpoch,
    required Map<String, Object?> payload,
  }) {
    if (payload.length != 5 ||
        payload['id'] != resourceId ||
        payload['householdId'] != familyId ||
        !isResourceId(resourceId) ||
        payload['name'] is! String ||
        (payload['name']! as String).trim().isEmpty ||
        (payload['name']! as String).length > 120 ||
        payload['colorArgb'] is! int ||
        (payload['colorArgb']! as int) < 0 ||
        (payload['colorArgb']! as int) > 0xffffffff ||
        payload['cloudAlias'] is! String ||
        database.raw.select('SELECT 1 FROM households WHERE id = ?', [
          familyId,
        ]).isEmpty) {
      throw StateError('Invalid child profile scope or format.');
    }
    final alias = CloudAlias.validate(
      payload['cloudAlias']! as String,
      childName: payload['name']! as String,
    );
    final existing = database.raw.select(
      'SELECT * FROM children WHERE id = ?',
      [resourceId],
    );
    if (existing.isNotEmpty) {
      final row = existing.single;
      if (row['household_id'] != familyId ||
          (row['is_placeholder'] == 0 &&
              (row['display_name'] != payload['name'] ||
                  row['color_argb'] != payload['colorArgb'] ||
                  row['cloud_alias'] != alias))) {
        // Child editing is not a supported operation. Preserve the existing
        // profile and cursor; never silently replace conflicting content.
        throw StateError('Child profile conflicts with existing data.');
      }
    }
    if (database.raw.select(
      'SELECT 1 FROM applied_operations WHERE operation_id = ?',
      [operationId],
    ).isNotEmpty) {
      return RemoteApplyResult.duplicate;
    }
    database.transaction(() {
      database.raw.execute(
        '''INSERT INTO children(id, household_id, display_name,
          color_argb, cloud_alias, is_placeholder) VALUES (?, ?, ?, ?, ?, 0)
          ON CONFLICT(id) DO UPDATE SET display_name=excluded.display_name,
          color_argb=excluded.color_argb, cloud_alias=excluded.cloud_alias, is_placeholder=0''',
        [resourceId, familyId, payload['name'], payload['colorArgb'], alias],
      );
      database.raw.execute(
        'INSERT INTO child_sync(child_id, key_epoch) VALUES (?, ?) ON CONFLICT(child_id) DO UPDATE SET key_epoch=excluded.key_epoch',
        [resourceId, keyEpoch],
      );
      database.raw.execute('INSERT INTO applied_operations VALUES (?, ?)', [
        operationId,
        DateTime.now().toUtc().toIso8601String(),
      ]);
    });
    return RemoteApplyResult.applied;
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
    final existingEvent = database.raw.select(
      'SELECT household_id FROM events WHERE id = ?',
      [event.id],
    );
    if (existingEvent.isNotEmpty &&
        existingEvent.single['household_id'] != event.householdId) {
      throw StateError('Invalid event scope.');
    }
    for (final childId in event.childIds) {
      if (!isResourceId(childId)) throw StateError('Invalid child reference.');
      final rows = database.raw.select(
        'SELECT household_id FROM children WHERE id = ?',
        [childId],
      );
      if (rows.isNotEmpty && rows.single['household_id'] != event.householdId) {
        throw StateError('Invalid child reference scope.');
      }
      database.raw.execute(
        '''INSERT OR IGNORE INTO children(id, household_id,
          display_name, color_argb, cloud_alias, is_placeholder) VALUES (?, ?, '', 0, ?, 1)''',
        [childId, event.householdId, 'pending-$childId'],
      );
    }
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
      localStart: tz.TZDateTime.from(
        DateTime.parse(row['local_start'] as String),
        tz.getLocation(row['timezone'] as String),
      ),
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
