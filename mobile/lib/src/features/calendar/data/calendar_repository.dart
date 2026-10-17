import 'dart:convert';

import '../domain/calendar_retention.dart';

import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/core/ids.dart';
import 'package:sarti_mobile/src/features/ai/cloud_alias.dart';
import 'package:sarti_mobile/src/features/calendar/domain/calendar_event.dart';
import 'package:sarti_mobile/src/features/sync/version_vector.dart';
import 'package:timezone/timezone.dart' as tz;

part 'calendar_retention_store.dart';
part 'calendar_recovery_store.dart';

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

class ParticipantProfile {
  const ParticipantProfile({
    required this.id,
    required this.name,
    required this.kind,
    required this.colorArgb,
    this.adultId,
  });
  final String id, name, kind;
  final int colorArgb;
  final String? adultId;
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
    this.participants = const [],
    this.sharedPrivateEventIds = const {},
  });

  final String householdId;
  final String name;
  final String calendarResourceId;
  final List<ChildProfile> children;
  final List<GuardianProfile> guardians;
  final List<CalendarEvent> events;
  final int openConflicts;
  final List<ParticipantProfile> participants;
  final Set<String> sharedPrivateEventIds;

  Map<String, String> get cloudChildAliases => {
    for (final child in children) child.name: child.cloudAlias,
  };
}

enum RemoteApplyResult { applied, duplicate, conflict, stale }

class CalendarRepository {
  CalendarRepository(
    this.database, {
    required this.deviceId,
    this.adultId,
    this.householdId,
  }) {
    final draft = database.raw.select(
      "SELECT value FROM app_preferences WHERE key='local-draft-adult'",
    );
    if (adultId != null && draft.isNotEmpty) {
      final old = draft.single['value'] as String;
      database.transaction(() {
        if (database.raw.select(
          "SELECT 1 FROM outbox WHERE state='uploaded' AND resource_id IN (SELECT resource_id FROM personal_calendars WHERE adult_id=?)",
          [old],
        ).isNotEmpty) {
          throw StateError('Published private identity cannot be rebound.');
        }
        database.raw.execute(
          'UPDATE personal_calendars SET adult_id=? WHERE adult_id=?',
          [adultId, old],
        );
        database.raw.execute(
          'UPDATE participant_profiles SET adult_id=? WHERE adult_id=?',
          [adultId, old],
        );
        for (final row in database.raw.select(
          "SELECT operation_id,payload_json FROM outbox WHERE kind='participant_upserted' AND state='pending'",
        )) {
          final payload = Map<String, Object?>.from(
            jsonDecode(row['payload_json'] as String) as Map,
          );
          if (payload['adultId'] == old) {
            payload['adultId'] = adultId;
            database.raw.execute(
              'UPDATE outbox SET payload_json=?,envelope_json=NULL WHERE operation_id=?',
              [jsonEncode(payload), row['operation_id']],
            );
          }
        }
        database.raw.execute(
          "DELETE FROM app_preferences WHERE key='local-draft-adult'",
        );
      });
    }
  }

  final SartiDatabase database;
  final String deviceId;
  final String? adultId;

  /// A pinned repository is safe to retain across an async household switch.
  final String? householdId;

  CalendarRepository forHousehold(String id) {
    if (database.raw.select('SELECT 1 FROM households WHERE id=?', [
      id,
    ]).isEmpty) {
      throw StateError('Unknown local household.');
    }
    return CalendarRepository(
      database,
      deviceId: deviceId,
      adultId: adultId,
      householdId: id,
    );
  }

  String? get selectedHouseholdId {
    if (householdId != null) return householdId;
    final selected = database.raw.select(
      "SELECT h.id FROM households h JOIN app_preferences p ON p.key='selected-household' AND p.value=h.id",
    );
    if (selected.isNotEmpty) return selected.single['id'] as String;
    final rows = database.raw.select(
      'SELECT id FROM households ORDER BY created_at,id LIMIT 1',
    );
    return rows.isEmpty ? null : rows.single['id'] as String;
  }

  void selectHousehold(String id) {
    if (householdId != null ||
        database.raw.select('SELECT 1 FROM households WHERE id=?', [
          id,
        ]).isEmpty) {
      throw StateError('Cannot select this household.');
    }
    database.raw.execute(
      "INSERT OR REPLACE INTO app_preferences VALUES ('selected-household',?)",
      [id],
    );
  }

  /// Retry an uncertain upload before consuming the device sequence elsewhere.
  List<FamilyCalendar> localFamilies() => database.raw
      .select(
        "SELECT h.id FROM households h ORDER BY EXISTS(SELECT 1 FROM outbox o WHERE o.family_id=h.id AND o.state='pending' AND o.envelope_json IS NOT NULL) DESC,h.created_at,h.id",
      )
      .map((row) => forHousehold(row['id'] as String).load()!)
      .toList();

  bool hasRevokedAccess(String id) {
    final rows = database.raw.select(
      'SELECT value FROM app_preferences WHERE key=?',
      ['family-access-$id'],
    );
    if (rows.isEmpty) return false;
    try {
      return (jsonDecode(rows.single['value'] as String) as Map)['role'] ==
          'revoked';
    } catch (_) {
      return true;
    }
  }

  FamilyCalendar? load() {
    final households = database.raw.select(
      'SELECT * FROM households WHERE id=?',
      [selectedHouseholdId],
    );
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
          'SELECT * FROM events WHERE household_id = ? AND deleted = 0 AND calendar_resource_id IN (?,?) ORDER BY local_start',
          [
            householdId,
            household['calendar_resource_id'] ?? householdId,
            personalResourceId ?? '',
          ],
        )
        .map(_eventFromRow)
        .toList();
    final calendarResource = household['calendar_resource_id'] as String?;
    final conflicts =
        database.raw.select(
              "SELECT count(*) AS total FROM conflicts WHERE status = 'open' AND resource_id IN (?,?)",
              [calendarResource ?? householdId, personalResourceId ?? ''],
            ).first['total']
            as int;
    return FamilyCalendar(
      householdId: householdId,
      name: household['display_name'] as String,
      calendarResourceId: calendarResource ?? householdId,
      children: children,
      guardians: guardians,
      events: events
          .where(
            (event) =>
                event.calendarResourceId == (calendarResource ?? householdId) ||
                event.calendarResourceId == personalResourceId,
          )
          .where(
            (event) => !database.raw.select(
              'SELECT 1 FROM appointment_shares WHERE shared_event_id=?',
              [event.id],
            ).isNotEmpty,
          )
          .toList(),
      participants: database.raw
          .select(
            'SELECT * FROM participant_profiles WHERE household_id=? ORDER BY display_name',
            [householdId],
          )
          .map(
            (r) => ParticipantProfile(
              id: r['id'] as String,
              name: r['display_name'] as String,
              kind: r['kind'] as String,
              colorArgb: r['color_argb'] as int,
              adultId: r['adult_id'] as String?,
            ),
          )
          .toList(),
      sharedPrivateEventIds: database.raw
          .select(
            'SELECT private_event_id FROM appointment_shares WHERE private_event_id IN (SELECT id FROM events WHERE calendar_resource_id=?)',
            [personalResourceId],
          )
          .map((r) => r['private_event_id'] as String)
          .toSet(),
      openConflicts: conflicts,
    );
  }

  FamilyCalendar createFamily({
    String name = 'My family',
    String ownerName = 'Me',
    String? familyId,
    String? calendarResourceId,
  }) {
    if (this.householdId != null) {
      throw StateError('Create a household from the account repository.');
    }
    // Recovery in another household does not block an independent new one.
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
      database.raw.execute('INSERT INTO app_preferences VALUES (?,?)', [
        'retention-new-$householdId',
        'true',
      ]);
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
    if (this.householdId == null) selectHousehold(householdId);
    return forHousehold(householdId).load()!;
  }

  /// Owner-confirmed, resource-scoped initial handoff. No event is edited.
  void queueGuardianHandoff({
    required String invitationId,
    required String profileResourceId,
    required Set<String> childResourceIds,
    Set<String> participantResourceIds = const {},
    required String guardianId,
    required String guardianName,
  }) {
    final family = load() ?? (throw StateError('No local family.'));
    if (family.openConflicts != 0) {
      throw StateError(
        'Resolve calendar conflicts before sharing an initial state.',
      );
    }
    if (!isResourceId(guardianId) ||
        guardianName.trim().isEmpty ||
        guardianName.length > 120) {
      throw ArgumentError('Invalid guardian profile.');
    }
    final marker = 'guardian-handoff-$invitationId';
    final prior = database.raw.select(
      'SELECT value FROM app_preferences WHERE key=?',
      [marker],
    );
    if (prior.isNotEmpty) {
      final ids = (jsonDecode(prior.single['value'] as String) as List)
          .cast<String>();
      if (ids.isNotEmpty &&
          ids.every(
            (id) => database.raw.select(
              'SELECT 1 FROM outbox WHERE operation_id=?',
              [id],
            ).isNotEmpty,
          )) {
        return;
      }
      // Recovery clears the old identity's outbox. Explicit retry must publish
      // a fresh scoped handoff, rather than trusting an orphaned progress flag.
    }
    final queuedIds = <String>[];
    final base = DateTime.now().toUtc();
    var order = 0;
    void queue(
      String resource,
      String kind,
      Object payload,
      Map<String, int> vector,
    ) {
      final operationId = newId();
      queuedIds.add(operationId);
      database.raw.execute(
        'INSERT INTO outbox(operation_id, family_id, resource_id, kind, payload_json, vector_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          operationId,
          family.householdId,
          resource,
          kind,
          jsonEncode(payload),
          jsonEncode(vector),
          base.add(Duration(microseconds: order++)).toIso8601String(),
        ],
      );
    }

    database.transaction(() {
      database.raw.execute(
        'INSERT INTO guardians(id, household_id, display_name) VALUES (?, ?, ?) ON CONFLICT(household_id,id) DO UPDATE SET display_name=excluded.display_name',
        [guardianId, family.householdId, guardianName.trim()],
      );
      for (final child in family.children.where(
        (c) => childResourceIds.contains(c.id),
      )) {
        queue(child.id, 'child_updated', {
          'id': child.id,
          'householdId': family.householdId,
          'name': child.name,
          'colorArgb': child.colorArgb,
          'cloudAlias': child.cloudAlias,
        }, _childVector(child.id));
      }
      for (final participant in family.participants.where(
        (p) => participantResourceIds.contains(p.id),
      )) {
        final version =
            database.raw.select(
                  'SELECT vector_json FROM participant_profiles WHERE id=?',
                  [participant.id],
                ).single['vector_json']
                as String;
        queue(participant.id, 'participant_upserted', {
          'id': participant.id,
          'householdId': family.householdId,
          'kind': participant.kind,
          'name': participant.name,
          'colorArgb': participant.colorArgb,
          'adultId': participant.adultId,
        }, Map<String, int>.from(jsonDecode(version) as Map));
      }
      for (final row in database.raw.select(
        'SELECT * FROM events WHERE household_id = ? AND calendar_resource_id = ?',
        [family.householdId, family.calendarResourceId],
      )) {
        final event = _eventFromRow(row);
        final version = database.raw.select(
          'SELECT * FROM event_versions WHERE event_id = ?',
          [event.id],
        );
        if (version.isEmpty) {
          throw StateError('The event version is unavailable.');
        }
        queue(
          family.calendarResourceId,
          event.deleted
              ? 'event_deleted'
              : version.single['retention_keep_vector'] != null &&
                    compareVectors(
                          _retentionVector(
                            version.single['retention_keep_vector'] as String,
                          ),
                          _retentionVector(
                            version.single['vector_json'] as String,
                          ),
                        ) ==
                        VectorRelation.equal
              ? 'retention_kept'
              : 'event_upserted',
          event.toJson(),
          Map<String, int>.from(
            jsonDecode(version.single['vector_json'] as String) as Map,
          ),
        );
      }
      for (final deletion in database.raw.select(
        'SELECT * FROM calendar_deletions WHERE household_id=? AND resource_id=?',
        [family.householdId, family.calendarResourceId],
      )) {
        queue(
          family.calendarResourceId,
          'retention_deleted',
          _deletionPayload(deletion),
          _retentionVector(deletion['vector_json'] as String),
        );
      }
      final vectorKey = 'household-vector-${family.householdId}';
      final stored = database.raw.select(
        'SELECT value FROM app_preferences WHERE key = ?',
        [vectorKey],
      );
      final vector = stored.isEmpty
          ? <String, int>{}
          : Map<String, int>.from(
              jsonDecode(stored.single['value'] as String) as Map,
            );
      vector[deviceId] = (vector[deviceId] ?? 0) + 1;
      queue(profileResourceId, 'household_shared', {
        'householdId': family.householdId,
        'name': family.name,
        'guardians': [
          for (final row in database.raw.select(
            'SELECT id, display_name FROM guardians WHERE household_id = ?',
            [family.householdId],
          ))
            {'id': row['id'], 'name': row['display_name']},
        ],
      }, vector);
      database.raw.execute(
        'INSERT OR REPLACE INTO app_preferences(key,value) VALUES (?,?)',
        [vectorKey, jsonEncode(vector)],
      );
      database.raw.execute(
        'INSERT OR REPLACE INTO app_preferences(key,value) VALUES (?,?)',
        [marker, jsonEncode(queuedIds)],
      );
    });
  }

  RemoteApplyResult applySharedHousehold({
    required String operationId,
    required String familyId,
    required String resourceId,
    required Map<String, int> vector,
    required Map<String, Object?> payload,
  }) {
    if (vector.isEmpty ||
        vector.length > 16 ||
        !vector.entries.every((e) => isResourceId(e.key) && e.value >= 0)) {
      throw StateError('Invalid family profile version.');
    }
    final catalog = database.raw.select(
      "SELECT 1 FROM resource_catalog WHERE resource_id=? AND family_id=? AND kind='family_profile'",
      [resourceId, familyId],
    );
    if (catalog.isEmpty ||
        payload.length != 3 ||
        payload['householdId'] != familyId ||
        payload['name'] is! String ||
        (payload['name'] as String).trim().isEmpty ||
        (payload['name'] as String).length > 120 ||
        payload['guardians'] is! List) {
      throw StateError('Invalid family profile.');
    }
    final guardians = payload['guardians'] as List;
    final ids = <String>{};
    if (guardians.length > 64) throw StateError('Too many guardian profiles.');
    for (final value in guardians) {
      if (value is! Map ||
          value.length != 2 ||
          value['id'] is! String ||
          !isResourceId(value['id'] as String) ||
          !ids.add(value['id'] as String) ||
          value['name'] is! String ||
          (value['name'] as String).trim().isEmpty ||
          (value['name'] as String).length > 120) {
        throw StateError('Invalid guardian profile.');
      }
    }
    if (database.raw.select('SELECT 1 FROM households WHERE id=?', [
      familyId,
    ]).isEmpty) {
      throw StateError('Family scope mismatch.');
    }
    if (database.raw.select(
      'SELECT 1 FROM applied_operations WHERE operation_id=?',
      [operationId],
    ).isNotEmpty) {
      return RemoteApplyResult.duplicate;
    }
    final vectorKey = 'household-vector-$familyId';
    final stored = database.raw.select(
      'SELECT value FROM app_preferences WHERE key=?',
      [vectorKey],
    );
    if (recoveryPending && stored.isEmpty) {
      throw StateError(
        'Recovered family profile requires verified causal history.',
      );
    }
    if (stored.isNotEmpty) {
      final relation = compareVectors(
        Map<String, int>.from(
          jsonDecode(stored.single['value'] as String) as Map,
        ),
        vector,
      );
      if (relation == VectorRelation.concurrent) {
        throw StateError('Concurrent family profiles require review.');
      }
      if (relation == VectorRelation.after ||
          relation == VectorRelation.equal) {
        return RemoteApplyResult.stale;
      }
    }
    database.transaction(() {
      database.raw.execute('UPDATE households SET display_name=? WHERE id=?', [
        payload['name'],
        familyId,
      ]);
      for (final value in guardians) {
        database.raw.execute(
          'INSERT INTO guardians(id, household_id, display_name) VALUES (?,?,?) ON CONFLICT(household_id,id) DO UPDATE SET display_name=excluded.display_name',
          [value['id'], familyId, value['name']],
        );
      }
      database.raw.execute(
        'INSERT OR REPLACE INTO app_preferences(key,value) VALUES (?,?)',
        [vectorKey, jsonEncode(vector)],
      );
      database.raw.execute(
        'INSERT OR REPLACE INTO app_preferences(key,value) VALUES (?,?)',
        ['guardian-ready-$familyId', 'true'],
      );
      database.raw.execute(
        'INSERT INTO applied_operations(operation_id, applied_at) VALUES (?, ?)',
        [operationId, DateTime.now().toUtc().toIso8601String()],
      );
    });
    return RemoteApplyResult.applied;
  }

  ChildProfile addChild(
    String name,
    int colorArgb, {
    String? cloudAlias,
    bool shareWithCalendarGuardians = false,
  }) {
    requireRecoveryReady();
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
  Map<String, int> _childVector(String id) {
    final rows = database.raw.select(
      'SELECT vector_json AS value FROM child_profile_versions WHERE child_id=?',
      [id],
    );
    return rows.isEmpty
        ? {deviceId: 1}
        : Map<String, int>.from(
            jsonDecode(rows.single['value'] as String) as Map,
          );
  }

  void updateChildColour(String id, int colour) {
    requireRecoveryReady();
    if (colour < 0 ||
        colour > 0xffffffff ||
        database.raw.select(
          'SELECT 1 FROM children WHERE id=? AND household_id=? AND is_placeholder=0',
          [id, load()?.householdId],
        ).isEmpty) {
      throw ArgumentError('Invalid child colour.');
    }
    database.transaction(() {
      database.raw.execute('UPDATE children SET color_argb=? WHERE id=?', [
        colour,
        id,
      ]);
      queueChildProfile(id);
    });
  }

  void updateChildName(String id, String name) {
    requireRecoveryReady();
    final value = name.trim();
    final rows = database.raw.select(
      'SELECT * FROM children WHERE id=? AND household_id=? AND is_placeholder=0',
      [id, load()?.householdId],
    );
    if (rows.isEmpty || value.isEmpty || value.length > 120) {
      throw ArgumentError('Invalid child profile.');
    }
    CloudAlias.validate(rows.single['cloud_alias'] as String, childName: value);
    database.transaction(() {
      database.raw.execute('UPDATE children SET display_name=? WHERE id=?', [
        value,
        id,
      ]);
      queueChildProfile(id);
    });
  }

  void saveFamilyDetails(String name, Map<String, String> guardianNames) {
    requireRecoveryReady();
    final family = load() ?? (throw StateError('Missing family.'));
    bool valid(String value) =>
        value.trim().isNotEmpty && value.trim().length <= 120;
    if (!valid(name) ||
        guardianNames.entries.any(
          (e) => !valid(e.value) || !family.guardians.any((g) => g.id == e.key),
        )) {
      throw ArgumentError('Invalid family profile.');
    }
    database.transaction(() {
      database.raw.execute('UPDATE households SET display_name=? WHERE id=?', [
        name.trim(),
        family.householdId,
      ]);
      for (final entry in guardianNames.entries) {
        database.raw.execute(
          'UPDATE guardians SET display_name=? WHERE id=? AND household_id=?',
          [entry.value.trim(), entry.key, family.householdId],
        );
      }
      database.raw.execute(
        'INSERT OR REPLACE INTO app_preferences VALUES (?,?)',
        ['family-profile-dirty-${family.householdId}', 'true'],
      );
      _queueFamilyDetails();
    });
  }

  void publishPendingFamilyDetails() {
    database.transaction(_queueFamilyDetails);
  }

  void _queueFamilyDetails() {
    final family = load();
    if (family == null || recoveryPending) return;
    final marker = 'family-profile-dirty-${family.householdId}';
    if (database.raw.select('SELECT 1 FROM app_preferences WHERE key=?', [
      marker,
    ]).isEmpty) {
      return;
    }
    final resource = database.raw.select(
      "SELECT resource_id FROM resource_catalog WHERE family_id=? AND kind='family_profile'",
      [family.householdId],
    );
    if (resource.isEmpty) return;
    final key = 'household-vector-${family.householdId}';
    final stored = database.raw.select(
      'SELECT value FROM app_preferences WHERE key=?',
      [key],
    );
    final vector = stored.isEmpty
        ? <String, int>{}
        : Map<String, int>.from(
            jsonDecode(stored.single['value'] as String) as Map,
          );
    vector[deviceId] = (vector[deviceId] ?? 0) + 1;
    database.raw.execute(
      'INSERT OR REPLACE INTO app_preferences VALUES (?,?)',
      [key, jsonEncode(vector)],
    );
    database.raw.execute(
      'INSERT INTO outbox(operation_id,family_id,resource_id,kind,payload_json,vector_json,created_at) VALUES (?,?,?,?,?,?,?)',
      [
        newId(),
        family.householdId,
        resource.single['resource_id'],
        'household_shared',
        jsonEncode({
          'householdId': family.householdId,
          'name': family.name,
          'guardians': [
            for (final g in family.guardians) {'id': g.id, 'name': g.name},
          ],
        }),
        jsonEncode(vector),
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
    database.raw.execute('DELETE FROM app_preferences WHERE key=?', [marker]);
  }

  void queueChildProfile(String childId) {
    final row = database.raw.select(
      'SELECT * FROM children WHERE id = ? AND is_placeholder = 0',
      [childId],
    ).single;
    final stored = database.raw.select(
      'SELECT vector_json AS value FROM child_profile_versions WHERE child_id=?',
      [childId],
    );
    final vector = stored.isEmpty
        ? <String, int>{}
        : Map<String, int>.from(
            jsonDecode(stored.single['value'] as String) as Map,
          );
    vector[deviceId] = (vector[deviceId] ?? 0) + 1;
    database.raw.execute(
      'INSERT OR REPLACE INTO child_profile_versions VALUES (?,?)',
      [childId, jsonEncode(vector)],
    );
    database.raw.execute(
      'INSERT INTO outbox(operation_id, family_id, resource_id, kind, payload_json, vector_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        newId(),
        row['household_id'],
        childId,
        stored.isEmpty ? 'child_created' : 'child_updated',
        jsonEncode({
          'id': childId,
          'householdId': row['household_id'],
          'name': row['display_name'],
          'colorArgb': row['color_argb'],
          'cloudAlias': row['cloud_alias'],
        }),
        jsonEncode(vector),
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
    Map<String, int>? vector,
    bool allowUpdate = false,
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
    if (vector != null) {
      if (vector.isEmpty ||
          vector.length > 16 ||
          !vector.entries.every((e) => isResourceId(e.key) && e.value >= 0)) {
        throw StateError('Invalid child version.');
      }
      final prior = database.raw.select(
        'SELECT vector_json AS value FROM child_profile_versions WHERE child_id=?',
        [resourceId],
      );
      if (prior.isNotEmpty) {
        final relation = compareVectors(
          Map<String, int>.from(
            jsonDecode(prior.single['value'] as String) as Map,
          ),
          vector,
        );
        if (relation == VectorRelation.concurrent) {
          final current = database.raw.select(
            'SELECT display_name,color_argb,cloud_alias FROM children WHERE id=?',
            [resourceId],
          );
          if (current.isEmpty ||
              current.single['display_name'] != payload['name'] ||
              current.single['color_argb'] != payload['colorArgb'] ||
              current.single['cloud_alias'] != alias) {
            throw StateError('Concurrent child colour edits require review.');
          }
          vector = mergeVectors(
            Map<String, int>.from(
              jsonDecode(prior.single['value'] as String) as Map,
            ),
            vector,
          );
        }
        if (relation != VectorRelation.before) return RemoteApplyResult.stale;
      }
    }
    final existing = database.raw.select(
      'SELECT * FROM children WHERE id = ?',
      [resourceId],
    );
    if (existing.isNotEmpty) {
      final row = existing.single;
      if (row['household_id'] != familyId ||
          (!allowUpdate &&
              row['is_placeholder'] == 0 &&
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
      if (vector != null) {
        database.raw.execute(
          'INSERT OR REPLACE INTO child_profile_versions VALUES (?,?)',
          [resourceId, jsonEncode(vector)],
        );
      }
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

  String? get currentAdultId {
    if (adultId != null) return adultId;
    final rows = database.raw.select(
      "SELECT value FROM app_preferences WHERE key='local-draft-adult'",
    );
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  String ensureDraftAdultId() {
    final existing = currentAdultId;
    if (existing != null) return existing;
    final id = newId();
    database.raw.execute(
      "INSERT INTO app_preferences VALUES ('local-draft-adult',?)",
      [id],
    );
    return id;
  }

  String? get personalResourceId {
    final actor = currentAdultId;
    if (actor == null) return null;
    final rows = database.raw.select(
      'SELECT resource_id FROM personal_calendars WHERE adult_id=? AND household_id=?',
      [actor, selectedHouseholdId],
    );
    return rows.isEmpty ? null : rows.single['resource_id'] as String;
  }

  String ensurePersonalCalendar() {
    final actor = ensureDraftAdultId();
    final family = load();
    if (!isResourceId(actor) || family == null) {
      throw StateError('Authenticate before creating private appointments.');
    }
    final existing = personalResourceId;
    if (existing != null) return existing;
    final id = newId();
    database.raw.execute('INSERT INTO personal_calendars VALUES (?,?,?)', [
      actor,
      family.householdId,
      id,
    ]);
    return id;
  }

  void _queueEvent(CalendarEvent event) {
    final vector = _nextVector(event.id);
    _saveEventRows(event, vector: vector);
    database.raw.execute(
      'INSERT INTO outbox(operation_id,family_id,resource_id,kind,payload_json,vector_json,created_at) VALUES (?,?,?,?,?,?,?)',
      [
        newId(),
        event.householdId,
        event.calendarResourceId,
        event.deleted ? 'event_deleted' : 'event_upserted',
        event.encode(),
        jsonEncode(vector),
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
  }

  void saveEvent(CalendarEvent event) {
    requireRecoveryReady();
    if (event.title.trim().isEmpty || event.durationMinutes <= 0) {
      throw ArgumentError('Event title and duration are required.');
    }
    final family = load();
    if (family == null ||
        event.householdId != family.householdId ||
        (event.calendarResourceId != family.calendarResourceId &&
            event.calendarResourceId != personalResourceId)) {
      throw StateError('Invalid calendar write scope.');
    }
    database.transaction(() => _queueEvent(event));
  }

  void saveReviewedEvents(List<CalendarEvent> events) {
    requireRecoveryReady();
    final family = load() ?? (throw StateError('Missing family.'));
    if (events.isEmpty ||
        events.length > 32 ||
        events.map((e) => e.id).toSet().length != events.length ||
        events.any(
          (e) =>
              e.title.trim().isEmpty ||
              e.durationMinutes <= 0 ||
              e.householdId != family.householdId ||
              e.calendarResourceId != family.calendarResourceId ||
              database.raw.select('SELECT 1 FROM events WHERE id=?', [
                e.id,
              ]).isNotEmpty,
        )) {
      throw ArgumentError('Invalid reviewed events.');
    }
    database.transaction(() {
      for (final event in events) {
        _queueEvent(event);
      }
    });
  }

  bool isShared(String eventId) => database.raw.select(
    'SELECT 1 FROM appointment_shares WHERE private_event_id=?',
    [eventId],
  ).isNotEmpty;

  ({CalendarEvent event, String vector})? householdCopy(String privateId) {
    final link = database.raw.select(
      'SELECT shared_event_id FROM appointment_shares WHERE private_event_id=?',
      [privateId],
    );
    if (link.isEmpty) return null;
    final rows = database.raw.select(
      'SELECT e.*,v.vector_json FROM events e JOIN event_versions v ON v.event_id=e.id WHERE e.id=?',
      [link.single['shared_event_id']],
    );
    if (rows.isEmpty) return null;
    return (
      event: _eventFromRow(rows.single),
      vector: rows.single['vector_json'] as String,
    );
  }

  void saveAdultAppointment(
    CalendarEvent event, {
    required bool share,
    String? reviewedSharedVector,
  }) {
    requireRecoveryReady();
    if (event.title.trim().isEmpty || event.durationMinutes <= 0) {
      throw ArgumentError('Event title and duration are required.');
    }
    final family = load()!;
    if (event.calendarResourceId != personalResourceId ||
        currentAdultId == null) {
      throw StateError('Invalid private author.');
    }
    database.transaction(() {
      final links = database.raw.select(
        'SELECT * FROM appointment_shares WHERE private_event_id=?',
        [event.id],
      );
      if (links.isNotEmpty) {
        final sharedId = links.single['shared_event_id'] as String;
        final stored = database.raw.select(
          'SELECT vector_json FROM event_versions WHERE event_id=?',
          [sharedId],
        );
        if (stored.isNotEmpty &&
            stored.single['vector_json'] != reviewedSharedVector &&
            compareVectors(
                  Map<String, int>.from(
                    jsonDecode(stored.single['vector_json'] as String) as Map,
                  ),
                  Map<String, int>.from(
                    jsonDecode(links.single['shared_vector_json'] as String)
                        as Map,
                  ),
                ) !=
                VectorRelation.equal) {
          throw StateError('Review the household copy before replacing it.');
        }
      }
      _queueEvent(event);
      if (share || links.isNotEmpty) {
        final sharedId = links.isEmpty
            ? newId()
            : links.single['shared_event_id'] as String;
        final copy = event.copyWith(
          id: sharedId,
          calendarResourceId: family.calendarResourceId,
          deleted: event.deleted || !share,
        );
        _queueEvent(copy);
        if (share) {
          final vector = database.raw.select(
            'SELECT vector_json FROM event_versions WHERE event_id=?',
            [sharedId],
          ).single['vector_json'];
          database.raw.execute(
            'INSERT OR REPLACE INTO appointment_shares VALUES (?,?,?)',
            [event.id, sharedId, vector],
          );
        } else {
          database.raw.execute(
            'DELETE FROM appointment_shares WHERE private_event_id=?',
            [event.id],
          );
        }
      }
    });
  }

  ParticipantProfile saveParticipant({
    String? id,
    required String name,
    required String kind,
    required int colour,
  }) {
    requireRecoveryReady();
    final family = load() ?? (throw StateError('Create a family first.'));
    if (!{'adult', 'pet'}.contains(kind) ||
        name.trim().isEmpty ||
        name.trim().length > 120 ||
        colour < 0 ||
        colour > 0xffffffff) {
      throw ArgumentError('Invalid participant profile.');
    }
    final actor = kind == 'adult' ? ensureDraftAdultId() : null;
    final profileId = id ?? newId();
    final previous = database.raw.select(
      'SELECT * FROM participant_profiles WHERE id=?',
      [profileId],
    );
    if (previous.isNotEmpty &&
        (previous.single['household_id'] != family.householdId ||
            previous.single['kind'] != kind)) {
      throw StateError('Profile scope mismatch.');
    }
    if (kind == 'adult' &&
        (actor == null ||
            (previous.isNotEmpty && previous.single['adult_id'] != actor))) {
      throw StateError('Only edit your own adult profile.');
    }
    final vector = previous.isEmpty
        ? <String, int>{}
        : Map<String, int>.from(
            jsonDecode(previous.single['vector_json'] as String) as Map,
          );
    vector[deviceId] = (vector[deviceId] ?? 0) + 1;
    database.transaction(() {
      database.raw.execute(
        'INSERT OR REPLACE INTO participant_profiles VALUES (?,?,?,?,?,?,?)',
        [
          profileId,
          family.householdId,
          kind,
          name.trim(),
          colour,
          kind == 'adult' ? actor : null,
          jsonEncode(vector),
        ],
      );
      database.raw.execute(
        'INSERT INTO outbox(operation_id,family_id,resource_id,kind,payload_json,vector_json,created_at) VALUES (?,?,?,?,?,?,?)',
        [
          newId(),
          family.householdId,
          profileId,
          'participant_upserted',
          jsonEncode({
            'id': profileId,
            'householdId': family.householdId,
            'kind': kind,
            'name': name.trim(),
            'colorArgb': colour,
            'adultId': kind == 'adult' ? actor : null,
          }),
          jsonEncode(vector),
          DateTime.now().toUtc().toIso8601String(),
        ],
      );
    });
    return ParticipantProfile(
      id: profileId,
      name: name.trim(),
      kind: kind,
      colorArgb: colour,
      adultId: kind == 'adult' ? actor : null,
    );
  }

  RemoteApplyResult applyParticipant({
    required String operationId,
    required String familyId,
    required String resourceId,
    required Map<String, int> vector,
    required Map<String, Object?> payload,
  }) {
    if (payload.length != 6 ||
        payload['id'] != resourceId ||
        payload['householdId'] != familyId ||
        !{'adult', 'pet'}.contains(payload['kind']) ||
        payload['name'] is! String ||
        (payload['name'] as String).trim().isEmpty ||
        (payload['name'] as String).length > 120 ||
        payload['colorArgb'] is! int ||
        (payload['colorArgb'] as int) < 0 ||
        (payload['colorArgb'] as int) > 0xffffffff ||
        (payload['kind'] == 'adult' &&
            (payload['adultId'] is! String ||
                !isResourceId(payload['adultId'] as String))) ||
        (payload['kind'] == 'pet' && payload['adultId'] != null) ||
        vector.isEmpty ||
        vector.length > 16 ||
        !vector.entries.every((e) => isResourceId(e.key) && e.value >= 0)) {
      throw StateError('Invalid participant profile.');
    }
    if (database.raw.select(
      'SELECT 1 FROM applied_operations WHERE operation_id=?',
      [operationId],
    ).isNotEmpty) {
      return RemoteApplyResult.duplicate;
    }
    final old = database.raw.select(
      'SELECT * FROM participant_profiles WHERE id=?',
      [resourceId],
    );
    if (old.isNotEmpty) {
      if (old.single['household_id'] != familyId ||
          old.single['kind'] != payload['kind'] ||
          old.single['adult_id'] != payload['adultId']) {
        throw StateError('Profile scope mismatch.');
      }
      final relation = compareVectors(
        Map<String, int>.from(
          jsonDecode(old.single['vector_json'] as String) as Map,
        ),
        vector,
      );
      if (relation == VectorRelation.concurrent) {
        throw StateError('Concurrent profile edits require review.');
      }
      if (relation != VectorRelation.before) return RemoteApplyResult.stale;
    }
    database.transaction(() {
      database.raw.execute(
        'INSERT OR REPLACE INTO participant_profiles VALUES (?,?,?,?,?,?,?)',
        [
          resourceId,
          familyId,
          payload['kind'],
          payload['name'],
          payload['colorArgb'],
          payload['adultId'],
          jsonEncode(vector),
        ],
      );
      database.raw.execute('INSERT INTO applied_operations VALUES (?,?)', [
        operationId,
        DateTime.now().toUtc().toIso8601String(),
      ]);
    });
    return RemoteApplyResult.applied;
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
    final deletion = database.raw.select(
      'SELECT * FROM calendar_deletions WHERE event_id=?',
      [event.id],
    );
    if (deletion.isNotEmpty) {
      final row = deletion.single;
      if (row['household_id'] != event.householdId ||
          row['resource_id'] != event.calendarResourceId) {
        throw StateError('Invalid deleted event scope.');
      }
      final relation = compareVectors(
        _retentionVector(row['vector_json'] as String),
        vector,
      );
      if (relation == VectorRelation.after ||
          relation == VectorRelation.equal) {
        return RemoteApplyResult.stale;
      }
      if (relation == VectorRelation.concurrent) {
        _recordRetentionConflict(event, vector, _deletionPayload(row));
        return RemoteApplyResult.conflict;
      }
    }
    if (recoveryPending &&
        database.raw.select(
          'SELECT 1 FROM events e LEFT JOIN event_versions v ON v.event_id=e.id WHERE e.id=? AND v.event_id IS NULL',
          [event.id],
        ).isNotEmpty) {
      throw StateError('Recovered appointment needs verified causal history.');
    }
    final localRows = database.raw.select(
      'SELECT operation_id, payload_json, vector_json FROM outbox WHERE resource_id = ? ORDER BY created_at DESC',
      [event.calendarResourceId],
    );
    var candidate = localRows.map((r) => Map<String, Object?>.from(r)).where((
      row,
    ) {
      final payload =
          jsonDecode(row['payload_json'] as String) as Map<String, dynamic>;
      return payload['id'] == event.id;
    }).firstOrNull;
    // Persisted causal state is authoritative after a downloaded resolution;
    // an older acknowledged outbox row must not reopen or overwrite it.
    final persisted = database.raw.select(
      'SELECT e.*,v.vector_json FROM events e JOIN event_versions v ON v.event_id=e.id WHERE e.id=?',
      [event.id],
    );
    if (persisted.isNotEmpty) {
      final stored = persisted.single;
      final same =
          candidate != null &&
          compareVectors(
                Map<String, int>.from(
                  jsonDecode(candidate['vector_json'] as String) as Map,
                ),
                Map<String, int>.from(
                  jsonDecode(stored['vector_json'] as String) as Map,
                ),
              ) ==
              VectorRelation.equal;
      candidate = {
        'operation_id': same ? candidate['operation_id'] : newId(),
        'payload_json': _eventFromRow(stored).encode(),
        'vector_json': stored['vector_json'],
      };
    }
    final matching = candidate;
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
        "SELECT * FROM conflicts WHERE status = 'open' AND resource_id IN (?,?) ORDER BY created_at",
        [load()?.calendarResourceId, personalResourceId],
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
    if (row['resource_id'] != load()?.calendarResourceId &&
        row['resource_id'] != personalResourceId) {
      throw StateError('Invalid conflict scope.');
    }
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
    final latest = database.raw.select(
      'SELECT vector_json FROM event_versions WHERE event_id=?',
      [selected.id],
    );
    if (latest.isNotEmpty) {
      final current = recoveryVector(latest.single['vector_json']);
      if (current == null ||
          (compareVectors(current, localVector) != VectorRelation.equal &&
              compareVectors(current, remoteVector) != VectorRelation.equal)) {
        throw StateError('This conflict changed. Review the latest event.');
      }
    }
    final resolvedVector = mergeVectors(localVector, remoteVector);
    resolvedVector[deviceId] = (resolvedVector[deviceId] ?? 0) + 1;
    database.transaction(() {
      database.raw.execute(
        "UPDATE conflicts SET status = 'resolved' WHERE id = ? AND status = 'open'",
        [conflictId],
      );
      _saveEventRows(next, vector: resolvedVector);
      _retireDominatedConflicts(
        next.id,
        next.calendarResourceId,
        resolvedVector,
      );
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
      trackReviewedRecoveryResolution();
    });
  }

  void _retireDominatedConflicts(
    String eventId,
    String resource,
    Map<String, int> vector,
  ) {
    for (final row in database.raw.select(
      "SELECT * FROM conflicts WHERE status='open' AND resource_id=?",
      [resource],
    )) {
      final local = _recoveryPayload(row['local_payload_json']);
      final remote = _recoveryPayload(row['remote_payload_json']);
      final lv = recoveryVector(row['local_vector_json']);
      final rv = recoveryVector(row['remote_vector_json']);
      if (local['id'] != eventId ||
          remote['id'] != eventId ||
          lv == null ||
          rv == null) {
        continue;
      }
      bool covered(Map<String, int> parent) => {
        VectorRelation.before,
        VectorRelation.equal,
      }.contains(compareVectors(parent, vector));
      if (covered(lv) && covered(rv)) {
        database.raw.execute(
          "UPDATE conflicts SET status='resolved' WHERE id=?",
          [row['id']],
        );
      }
    }
  }

  void _saveRemote(
    CalendarEvent event,
    String operationId,
    Map<String, int> vector,
  ) {
    database.transaction(() {
      _saveEventRows(event, vector: vector);
      _retireRetentionConflict(event.id, vector);
      _retireDominatedConflicts(event.id, event.calendarResourceId, vector);
      database.raw.execute('INSERT INTO applied_operations VALUES (?, ?)', [
        operationId,
        DateTime.now().toUtc().toIso8601String(),
      ]);
    });
  }

  void _saveEventRows(CalendarEvent event, {Map<String, int>? vector}) {
    final removed = database.raw.select(
      'SELECT * FROM calendar_deletions WHERE event_id=?',
      [event.id],
    );
    if (removed.isNotEmpty) {
      if (vector == null ||
          removed.single['resource_id'] != event.calendarResourceId ||
          removed.single['household_id'] != event.householdId ||
          compareVectors(
                _retentionVector(removed.single['vector_json'] as String),
                vector,
              ) !=
              VectorRelation.before) {
        throw StateError(
          'Deleted event requires a causally newer reviewed edit.',
        );
      }
      database.raw.execute('DELETE FROM calendar_deletions WHERE event_id=?', [
        event.id,
      ]);
    }
    final existingEvent = database.raw.select(
      'SELECT household_id, calendar_resource_id FROM events WHERE id = ?',
      [event.id],
    );
    if (existingEvent.isNotEmpty &&
        (existingEvent.single['household_id'] != event.householdId ||
            existingEvent.single['calendar_resource_id'] !=
                event.calendarResourceId)) {
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
    database.raw.execute('DELETE FROM event_participants WHERE event_id=?', [
      event.id,
    ]);
    for (final participant in event.participants) {
      if (!isResourceId(participant.id) ||
          !{'adult', 'pet'}.contains(participant.kind)) {
        throw StateError('Invalid participant reference.');
      }
      final profile = database.raw.select(
        'SELECT household_id,kind FROM participant_profiles WHERE id=?',
        [participant.id],
      );
      if (profile.isNotEmpty &&
          (profile.single['household_id'] != event.householdId ||
              profile.single['kind'] != participant.kind)) {
        throw StateError('Participant scope mismatch.');
      }
      database.raw.execute('INSERT INTO event_participants VALUES (?,?,?)', [
        event.id,
        participant.id,
        participant.kind,
      ]);
    }
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
      participants: database.raw
          .select(
            'SELECT profile_id,kind FROM event_participants WHERE event_id=?',
            [eventId],
          )
          .map(
            (r) => EventParticipant(
              id: r['profile_id'] as String,
              kind: r['kind'] as String,
            ),
          )
          .toList(),
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
