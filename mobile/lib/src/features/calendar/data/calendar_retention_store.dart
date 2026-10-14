part of 'calendar_repository.dart';

Map<String, int> _retentionVector(String value) =>
    Map<String, int>.from(jsonDecode(value) as Map);
Map<String, Object?> _deletionPayload(dynamic row) => {
  'id': row['event_id'],
  'householdId': row['household_id'],
  'resourceId': row['resource_id'],
  'vector': jsonDecode(row['vector_json'] as String),
  'deletedAt': row['deleted_at'],
};

extension CalendarRetentionStore on CalendarRepository {
  Map<String, dynamic>? get retentionPolicy {
    final family = load();
    if (family == null) return null;
    final rows = database.raw.select(
      'SELECT value FROM app_preferences WHERE key=?',
      ['retention-policy-${family.householdId}'],
    );
    return rows.isEmpty
        ? null
        : Map<String, dynamic>.from(
            jsonDecode(rows.single['value'] as String) as Map,
          );
  }

  void cacheRetentionPolicy(Map<String, dynamic> policy) {
    final family = load() ?? (throw StateError('No family.'));
    CalendarRetention.values.byName(policy['period'] as String);
    if (policy['enabled'] is! bool ||
        policy['revision'] is! int ||
        (policy['revision'] as int) < 0 ||
        policy['can_manage'] is! bool) {
      throw const FormatException('Invalid calendar retention policy.');
    }
    final old = retentionPolicy;
    if (old != null && (old['revision'] as int) > (policy['revision'] as int)) {
      throw StateError('Stale retention policy.');
    }
    database.raw.execute(
      'INSERT OR REPLACE INTO app_preferences VALUES (?,?)',
      ['retention-policy-${family.householdId}', jsonEncode(policy)],
    );
  }

  List<CalendarEvent> retentionCandidates(
    CalendarRetention period,
    DateTime now,
  ) {
    final family = load();
    if (family == null) return [];
    return database.raw
        .select(
          'SELECT * FROM events WHERE household_id=? AND calendar_resource_id IN (?,?)',
          [
            family.householdId,
            family.calendarResourceId,
            personalResourceId ?? '',
          ],
        )
        .map(_eventFromRow)
        .where((e) => calendarHistoryExpired(e, period, now))
        .toList();
  }

  bool _hasPendingEvent(String id) => database.raw
      .select("SELECT payload_json FROM outbox WHERE state='pending'")
      .any((r) => (jsonDecode(r['payload_json'] as String) as Map)['id'] == id);

  bool _retentionBlocked(
    CalendarEvent event, {
    bool ignoreRetentionConflict = false,
  }) {
    final version = database.raw.select(
      'SELECT vector_json,retention_keep_vector FROM event_versions WHERE event_id=?',
      [event.id],
    );
    if (version.isNotEmpty &&
        version.single['retention_keep_vector'] != null &&
        compareVectors(
              _retentionVector(
                version.single['retention_keep_vector'] as String,
              ),
              _retentionVector(version.single['vector_json'] as String),
            ) ==
            VectorRelation.equal) {
      return true;
    }
    if (_hasPendingEvent(event.id)) return true;
    if (database.raw.select(
          "SELECT 1 FROM conflicts WHERE resource_id=? AND status='open'",
          [event.calendarResourceId],
        ).isNotEmpty ||
        (!ignoreRetentionConflict &&
            database.raw.select(
              'SELECT 1 FROM retention_conflicts WHERE event_id=?',
              [event.id],
            ).isNotEmpty)) {
      return true;
    }
    final links = database.raw.select(
      'SELECT * FROM appointment_shares WHERE private_event_id=? OR shared_event_id=?',
      [event.id, event.id],
    );
    for (final link in links) {
      final rows = database.raw.select(
        'SELECT vector_json FROM event_versions WHERE event_id=?',
        [link['shared_event_id']],
      );
      if (rows.isEmpty ||
          _hasPendingEvent(link['private_event_id'] as String) ||
          _hasPendingEvent(link['shared_event_id'] as String) ||
          compareVectors(
                _retentionVector(rows.single['vector_json'] as String),
                _retentionVector(link['shared_vector_json'] as String),
              ) !=
              VectorRelation.equal) {
        return true;
      }
    }
    return false;
  }

  /// Called only after current authenticated policy/authority and complete catch-up.
  List<String> sweepRetention(DateTime now, {required bool canAdminister}) {
    final policy = retentionPolicy;
    if (policy == null || policy['enabled'] != true) return [];
    final family = load()!;
    final period = CalendarRetention.values.byName(policy['period'] as String);
    final deleted = <String>[];
    database.transaction(() {
      for (final event in retentionCandidates(period, now).take(100)) {
        if (event.calendarResourceId == family.calendarResourceId &&
            !canAdminister) {
          continue;
        }
        if (event.calendarResourceId != family.calendarResourceId &&
            event.calendarResourceId != personalResourceId) {
          continue;
        }
        if (_retentionBlocked(event)) continue;
        final vector = _nextVector(event.id);
        _queueRetentionDeletion(
          event.id,
          family.householdId,
          event.calendarResourceId,
          vector,
          now,
        );
        deleted.add(event.id);
      }
    });
    return deleted;
  }

  void _queueRetentionDeletion(
    String id,
    String family,
    String resource,
    Map<String, int> vector,
    DateTime now,
  ) {
    final payload = {
      'id': id,
      'householdId': family,
      'resourceId': resource,
      'vector': vector,
      'deletedAt': now.toUtc().toIso8601String(),
    };
    _removeRetainedContent(payload);
    database.raw.execute(
      'INSERT INTO outbox(operation_id,family_id,resource_id,kind,payload_json,vector_json,created_at) VALUES (?,?,?,?,?,?,?)',
      [
        newId(),
        family,
        resource,
        'retention_deleted',
        jsonEncode(payload),
        jsonEncode(vector),
        now.toUtc().toIso8601String(),
      ],
    );
  }

  void _removeRetainedContent(Map<String, Object?> payload) {
    final id = payload['id'] as String;
    // Keep exact pending retry bytes; remove obsolete acknowledged event bodies.
    for (final row in database.raw.select(
      "SELECT operation_id,payload_json FROM outbox WHERE state='uploaded'",
    )) {
      if ((jsonDecode(row['payload_json'] as String) as Map)['id'] == id) {
        database.raw.execute('DELETE FROM outbox WHERE operation_id=?', [
          row['operation_id'],
        ]);
      }
    }
    for (final row in database.raw.select(
      "SELECT id,local_payload_json,remote_payload_json FROM conflicts WHERE status='resolved'",
    )) {
      if ((jsonDecode(row['local_payload_json'] as String) as Map)['id'] ==
              id ||
          (jsonDecode(row['remote_payload_json'] as String) as Map)['id'] ==
              id) {
        database.raw.execute('DELETE FROM conflicts WHERE id=?', [row['id']]);
      }
    }
    database.raw.execute(
      'DELETE FROM appointment_shares WHERE private_event_id=? OR shared_event_id=?',
      [id, id],
    );
    database.raw.execute('DELETE FROM events WHERE id=?', [id]);
    database.raw.execute(
      'INSERT OR REPLACE INTO calendar_deletions VALUES (?,?,?,?,?)',
      [
        id,
        payload['householdId'],
        payload['resourceId'],
        jsonEncode(payload['vector']),
        payload['deletedAt'],
      ],
    );
  }

  void _recordRetentionConflict(
    CalendarEvent event,
    Map<String, int> eventVector,
    Map<String, Object?> deletion,
  ) {
    final prior = database.raw.select(
      'SELECT * FROM retention_conflicts WHERE event_id=?',
      [event.id],
    );
    if (prior.isNotEmpty) {
      if (prior.single['deletion_json'] == jsonEncode(deletion) &&
          prior.single['event_json'] == event.encode() &&
          prior.single['event_vector_json'] == jsonEncode(eventVector)) {
        return;
      }
      throw StateError(
        'Resolve existing retention alternatives before applying another edit.',
      );
    }
    database.raw.execute('INSERT INTO retention_conflicts VALUES (?,?,?,?,?)', [
      event.id,
      event.calendarResourceId,
      jsonEncode(deletion),
      event.encode(),
      jsonEncode(eventVector),
    ]);
  }

  RemoteApplyResult applyRetentionDeletion({
    required String operationId,
    required String familyId,
    required String resourceId,
    required Map<String, int> vector,
    required Map<String, Object?> payload,
  }) {
    final family = load();
    if (family == null ||
        family.householdId != familyId ||
        (resourceId != family.calendarResourceId &&
            resourceId != personalResourceId) ||
        payload.length != 5 ||
        !isResourceId(payload['id'] as String? ?? '') ||
        payload['householdId'] != familyId ||
        payload['resourceId'] != resourceId ||
        vector.isEmpty ||
        vector.length > 16 ||
        !vector.entries.every((e) => isResourceId(e.key) && e.value >= 0) ||
        payload['vector'] is! Map ||
        compareVectors(
              Map<String, int>.from(payload['vector'] as Map),
              vector,
            ) !=
            VectorRelation.equal ||
        payload['deletedAt'] is! String ||
        DateTime.tryParse(payload['deletedAt'] as String) == null) {
      throw const FormatException('Invalid retention deletion.');
    }
    if (database.raw.select(
      'SELECT 1 FROM applied_operations WHERE operation_id=?',
      [operationId],
    ).isNotEmpty) {
      return RemoteApplyResult.duplicate;
    }
    final id = payload['id'] as String;
    final old = database.raw.select(
      'SELECT * FROM calendar_deletions WHERE event_id=?',
      [id],
    );
    if (old.isNotEmpty) {
      if (old.single['household_id'] != familyId ||
          old.single['resource_id'] != resourceId) {
        throw StateError('Deletion scope mismatch.');
      }
      final relation = compareVectors(
        _retentionVector(old.single['vector_json'] as String),
        vector,
      );
      if (relation == VectorRelation.after ||
          relation == VectorRelation.equal) {
        return RemoteApplyResult.stale;
      }
      // Concurrent deletion versus deletion has no differing content; merge causality.
      payload = {
        ...payload,
        'vector': mergeVectors(
          _retentionVector(old.single['vector_json'] as String),
          vector,
        ),
      };
    }
    if (database.raw.select(
      'SELECT 1 FROM events e LEFT JOIN event_versions v ON v.event_id=e.id WHERE e.id=? AND v.event_id IS NULL',
      [id],
    ).isNotEmpty) {
      throw StateError(
        'Recovered appointment causal state requires validation before deletion.',
      );
    }
    final rows = database.raw.select(
      'SELECT e.*,v.vector_json FROM events e JOIN event_versions v ON v.event_id=e.id WHERE e.id=?',
      [id],
    );
    if (rows.isNotEmpty) {
      final event = _eventFromRow(rows.single);
      if (event.householdId != familyId ||
          event.calendarResourceId != resourceId) {
        throw StateError('Deletion scope mismatch.');
      }
      final existing = _retentionVector(rows.single['vector_json'] as String);
      final relation = compareVectors(existing, vector);
      if (relation == VectorRelation.after ||
          relation == VectorRelation.equal) {
        return RemoteApplyResult.stale;
      }
      if (relation == VectorRelation.concurrent ||
          _retentionBlocked(
            event,
            ignoreRetentionConflict: _dominatesRetentionConflict(id, vector),
          )) {
        _recordRetentionConflict(event, existing, payload);
        return RemoteApplyResult.conflict;
      }
    }
    database.transaction(() {
      _retireRetentionConflict(id, vector);
      _removeRetainedContent(payload);
      database.raw.execute('INSERT INTO applied_operations VALUES (?,?)', [
        operationId,
        DateTime.now().toUtc().toIso8601String(),
      ]);
    });
    return RemoteApplyResult.applied;
  }

  bool _dominatesRetentionConflict(String id, Map<String, int> vector) {
    final rows = database.raw.select(
      'SELECT * FROM retention_conflicts WHERE event_id=?',
      [id],
    );
    if (rows.isEmpty) return false;
    final row = rows.single;
    final deletion = jsonDecode(row['deletion_json'] as String) as Map;
    final combined = mergeVectors(
      _retentionVector(row['event_vector_json'] as String),
      Map<String, int>.from(deletion['vector'] as Map),
    );
    return compareVectors(combined, vector) == VectorRelation.before;
  }

  void _retireRetentionConflict(String id, Map<String, int> vector) {
    if (_dominatesRetentionConflict(id, vector)) {
      database.raw.execute('DELETE FROM retention_conflicts WHERE event_id=?', [
        id,
      ]);
    }
  }

  List<Map<String, Object?>> retentionConflicts() => database.raw
      .select('SELECT * FROM retention_conflicts WHERE resource_id IN (?,?)', [
        load()?.calendarResourceId,
        personalResourceId,
      ])
      .map((r) {
        final result = Map<String, Object?>.from(r);
        final current = database.raw.select(
          'SELECT e.*,v.vector_json FROM events e JOIN event_versions v ON v.event_id=e.id WHERE e.id=?',
          [r['event_id']],
        );
        if (current.isNotEmpty) {
          result['event_json'] = _eventFromRow(current.single).encode();
          result['review_vector_json'] = current.single['vector_json'];
        } else {
          result['review_vector_json'] = r['event_vector_json'];
        }
        return result;
      })
      .toList();

  void resolveRetentionConflict(
    String id, {
    required bool keep,
    String? reviewedVector,
  }) {
    final rows = retentionConflicts()
        .where((r) => r['event_id'] == id)
        .toList();
    if (rows.isEmpty) throw StateError('Conflict is no longer available.');
    final row = rows.single;
    final event = CalendarEvent.fromJson(
      Map<String, Object?>.from(jsonDecode(row['event_json'] as String) as Map),
    );
    if (reviewedVector != null && reviewedVector != row['review_vector_json']) {
      throw StateError(
        'Review the latest appointment before resolving retention.',
      );
    }
    final deletion = Map<String, Object?>.from(
      jsonDecode(row['deletion_json'] as String) as Map,
    );
    final vector = mergeVectors(
      mergeVectors(
        _retentionVector(row['event_vector_json'] as String),
        _retentionVector(row['review_vector_json'] as String),
      ),
      Map<String, int>.from(deletion['vector'] as Map),
    );
    vector[deviceId] = (vector[deviceId] ?? 0) + 1;
    database.transaction(() {
      database.raw.execute('DELETE FROM retention_conflicts WHERE event_id=?', [
        id,
      ]);
      if (keep) {
        _saveEventRows(event, vector: vector);
        database.raw.execute(
          'UPDATE event_versions SET retention_keep_vector=? WHERE event_id=?',
          [jsonEncode(vector), id],
        );
        database.raw.execute(
          'INSERT INTO outbox(operation_id,family_id,resource_id,kind,payload_json,vector_json,created_at) VALUES (?,?,?,?,?,?,?)',
          [
            newId(),
            event.householdId,
            event.calendarResourceId,
            'retention_kept',
            event.encode(),
            jsonEncode(vector),
            DateTime.now().toUtc().toIso8601String(),
          ],
        );
      } else {
        _queueRetentionDeletion(
          id,
          event.householdId,
          event.calendarResourceId,
          vector,
          DateTime.now().toUtc(),
        );
      }
    });
  }
}
