part of 'calendar_repository.dart';

Map<String, int>? recoveryVector(Object? encoded) {
  try {
    final value = encoded is String ? jsonDecode(encoded) : encoded;
    if (value is! Map || value.isEmpty || value.length > 16) return null;
    final vector = Map<String, int>.from(value);
    return vector.entries.every((e) => isResourceId(e.key) && e.value >= 0)
        ? vector
        : null;
  } catch (_) {
    return null;
  }
}

Map<String, Object?> _recoveryPayload(Object? value) {
  try {
    return Map<String, Object?>.from(jsonDecode(value as String) as Map);
  } catch (_) {
    return {};
  }
}

class RecoveredChange {
  const RecoveredChange(
    this.id,
    this.resourceId,
    this.kind,
    this.title,
    this.status,
    this.reason,
    this.fingerprint,
  );
  final String id, resourceId, kind, title, status, fingerprint;
  final String? reason;
}

extension CalendarRecoveryStore on CalendarRepository {
  Map<String, Object?>? get recoveryState {
    final rows = database.raw.select('SELECT * FROM recovery_state LIMIT 1');
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.single);
  }

  bool get recoveryPending =>
      recoveryState != null && recoveryState!['phase'] != 'ready';
  void requireRecoveryReady() {
    if (recoveryPending) {
      throw StateError('Review recovery before changing this calendar.');
    }
  }

  void setRecoveryPhase(String phase, {String? reason}) {
    database.raw.execute('UPDATE recovery_state SET phase=?,reason=?', [
      phase,
      reason,
    ]);
  }

  /// Called inside the staging transaction, never against the live source.
  void initializeFamilyRecovery() {
    final family = load() ?? (throw StateError('Missing recovery family.'));
    final catalog = database.raw.select('SELECT * FROM resource_catalog');
    if (catalog.any(
          (r) =>
              r['family_id'] != family.householdId ||
              r['kind'] == 'personal_calendar',
        ) ||
        database.raw.select(
          'SELECT 1 FROM events WHERE household_id!=? OR calendar_resource_id!=?',
          [family.householdId, family.calendarResourceId],
        ).isNotEmpty ||
        database.raw.select(
          'SELECT 1 FROM recovery_intents WHERE family_id!=?',
          [family.householdId],
        ).isNotEmpty) {
      throw StateError('Recovery content is outside the family scope.');
    }
    final known = {
      family.calendarResourceId,
      ...catalog.map((r) => r['resource_id'] as String),
      ...database.raw
          .select('SELECT id FROM children WHERE household_id=?', [
            family.householdId,
          ])
          .map((r) => r['id'] as String),
      ...database.raw
          .select('SELECT id FROM participant_profiles WHERE household_id=?', [
            family.householdId,
          ])
          .map((r) => r['id'] as String),
    };
    for (final key in database.raw.select('SELECT * FROM resource_keys')) {
      if (!known.contains(key['resource_id']) ||
          base64Url.decode(key['key_base64'] as String).length != 32) {
        throw StateError('Recovery key scope is invalid.');
      }
    }
    final previous = recoveryState;
    var blocked = previous?['phase'] == 'blocked';
    for (final row in database.raw.select(
      'SELECT e.id,v.vector_json,v.retention_keep_vector FROM events e LEFT JOIN event_versions v ON v.event_id=e.id',
    )) {
      if (recoveryVector(row['vector_json']) == null ||
          (row['retention_keep_vector'] != null &&
              recoveryVector(row['retention_keep_vector']) == null)) {
        blocked = true;
      }
    }
    for (final row in database.raw.select(
      'SELECT vector_json FROM calendar_deletions',
    )) {
      if (recoveryVector(row['vector_json']) == null) blocked = true;
    }
    database.raw.execute(
      'INSERT OR REPLACE INTO recovery_state VALUES (?,?,?,?,?)',
      [
        family.householdId,
        blocked ? 'blocked' : 'paused',
        previous?['snapshot_at'],
        previous?['profile_vector_json'],
        blocked ? 'missing_causal_history' : null,
      ],
    );
    // Re-exported recovery: recognize already acknowledged intents, but never
    // reuse a queued operation's former device binding on the replacement.
    final queuedBefore = database.raw
        .select(
          "SELECT queued_operation_id FROM recovery_intents WHERE status='queued'",
        )
        .map((r) => r['queued_operation_id'])
        .toSet();
    for (final intent in database.raw.select(
      "SELECT * FROM recovery_intents WHERE status='queued'",
    )) {
      final op = database.raw.select(
        'SELECT * FROM outbox WHERE operation_id=?',
        [intent['queued_operation_id']],
      );
      if (op.isNotEmpty && op.single['state'] == 'uploaded') {
        database.raw.execute(
          "UPDATE recovery_intents SET status='done',queued_operation_id=NULL WHERE source_operation_id=?",
          [intent['source_operation_id']],
        );
      } else {
        if (op.isNotEmpty) {
          database.raw.execute(
            'UPDATE recovery_intents SET kind=?,payload_json=?,vector_json=? WHERE source_operation_id=?',
            [
              op.single['kind'],
              op.single['payload_json'],
              op.single['vector_json'],
              intent['source_operation_id'],
            ],
          );
        }
        database.raw.execute(
          "UPDATE recovery_intents SET status='pending',queued_operation_id=NULL,reviewed_payload_json=NULL,reviewed_vector_json=NULL WHERE source_operation_id=?",
          [intent['source_operation_id']],
        );
      }
    }
    for (final row in database.raw.select(
      "SELECT * FROM outbox WHERE state='pending'",
    )) {
      if (row['family_id'] != family.householdId) {
        throw StateError('Recovery operation scope is invalid.');
      }
      if (queuedBefore.contains(row['operation_id'])) continue;
      if (row['kind'] == 'family_created') {
        continue; // Existing server family; not a content mutation.
      }
      final old = database.raw.select(
        'SELECT 1 FROM recovery_intents WHERE source_operation_id=? OR queued_operation_id=?',
        [row['operation_id'], row['operation_id']],
      );
      if (old.isNotEmpty) continue;
      final valid = _validRecoveryIntent(Map<String, Object?>.from(row));
      if (valid &&
          (row['kind'] == 'child_created' || row['kind'] == 'child_updated')) {
        final payload = _recoveryPayload(row['payload_json']);
        final child = database.raw.select('SELECT * FROM children WHERE id=?', [
          row['resource_id'],
        ]);
        if (child.isNotEmpty &&
            child.single['household_id'] == family.householdId &&
            child.single['display_name'] == payload['name'] &&
            child.single['color_argb'] == payload['colorArgb'] &&
            child.single['cloud_alias'] == payload['cloudAlias']) {
          final versions = database.raw.select(
            'SELECT vector_json FROM child_profile_versions WHERE child_id=?',
            [row['resource_id']],
          );
          if (versions.isEmpty) {
            database.raw.execute(
              'INSERT INTO child_profile_versions VALUES (?,?)',
              [row['resource_id'], row['vector_json']],
            );
          }
        }
      }
      database.raw.execute(
        'INSERT OR IGNORE INTO recovery_intents(source_operation_id,family_id,resource_id,kind,payload_json,vector_json,status,queued_operation_id,reason) VALUES (?,?,?,?,?,?,?,?,?)',
        [
          row['operation_id'],
          family.householdId,
          row['resource_id'],
          row['kind'],
          row['payload_json'],
          row['vector_json'],
          valid ? 'pending' : 'quarantined',
          null,
          valid ? null : 'unverified_intent',
        ],
      );
    }
    if (database.raw
        .select(
          'SELECT 1 FROM children c LEFT JOIN child_profile_versions v ON v.child_id=c.id WHERE c.is_placeholder=0 AND v.child_id IS NULL',
        )
        .isNotEmpty) {
      setRecoveryPhase('blocked', reason: 'missing_causal_history');
    }
    // Drop former device operation bindings, retaining only protected intent.
    database.raw.execute(
      'UPDATE recovery_intents SET queued_operation_id=NULL WHERE status!=\'queued\'',
    );
    final profile = recoveryVector(recoveryState?['profile_vector_json']);
    if (profile != null) {
      database.raw.execute(
        'INSERT OR REPLACE INTO app_preferences VALUES (?,?)',
        ['household-vector-${family.householdId}', jsonEncode(profile)],
      );
    }
  }

  bool _validRecoveryIntent(Map<String, Object?> row) {
    try {
      final family = load()!;
      final payload = Map<String, Object?>.from(
        jsonDecode(row['payload_json'] as String) as Map,
      );
      if (row['family_id'] != family.householdId ||
          !isResourceId(row['resource_id'] as String) ||
          recoveryVector(row['vector_json']) == null) {
        return false;
      }
      final kind = row['kind'];
      if ({
        'event_upserted',
        'event_deleted',
        'conflict_resolved',
        'retention_kept',
      }.contains(kind)) {
        final event = CalendarEvent.fromJson(payload);
        return isResourceId(event.id) &&
            event.householdId == family.householdId &&
            event.calendarResourceId == family.calendarResourceId &&
            row['resource_id'] == event.calendarResourceId &&
            event.durationMinutes > 0 &&
            event.title.trim().isNotEmpty;
      }
      if (kind == 'retention_deleted') {
        return payload.length == 5 &&
            payload['householdId'] == family.householdId &&
            payload['resourceId'] == family.calendarResourceId &&
            row['resource_id'] == family.calendarResourceId &&
            isResourceId(payload['id'] as String? ?? '') &&
            payload['deletedAt'] is String &&
            DateTime.tryParse(payload['deletedAt'] as String) != null &&
            recoveryVector(payload['vector']) != null &&
            compareVectors(
                  recoveryVector(payload['vector'])!,
                  recoveryVector(row['vector_json'])!,
                ) ==
                VectorRelation.equal;
      }
      if (kind == 'child_created' || kind == 'child_updated') {
        return payload.length == 5 &&
            payload['id'] == row['resource_id'] &&
            payload['householdId'] == family.householdId &&
            payload['name'] is String &&
            (payload['name'] as String).trim().isNotEmpty &&
            (payload['name'] as String).length <= 120 &&
            payload['colorArgb'] is int &&
            (payload['colorArgb'] as int) >= 0 &&
            (payload['colorArgb'] as int) <= 0xffffffff &&
            payload['cloudAlias'] is String &&
            CloudAlias.validate(
                  payload['cloudAlias'] as String,
                  childName: payload['name'] as String,
                ) ==
                payload['cloudAlias'];
      }
      if (kind == 'participant_upserted') {
        return payload.length == 6 &&
            payload['id'] == row['resource_id'] &&
            payload['householdId'] == family.householdId &&
            {'adult', 'pet'}.contains(payload['kind']) &&
            payload['name'] is String &&
            (payload['name'] as String).trim().isNotEmpty &&
            (payload['name'] as String).length <= 120 &&
            payload['colorArgb'] is int &&
            (payload['colorArgb'] as int) >= 0 &&
            (payload['colorArgb'] as int) <= 0xffffffff &&
            (payload['kind'] == 'pet'
                ? payload['adultId'] == null
                : isResourceId(payload['adultId'] as String? ?? ''));
      }
      if (kind == 'household_shared') {
        final resources = database.raw.select(
          "SELECT 1 FROM resource_catalog WHERE resource_id=? AND family_id=? AND kind='family_profile'",
          [row['resource_id'], family.householdId],
        );
        final people = payload['guardians'];
        return resources.isNotEmpty &&
            payload.length == 3 &&
            payload['householdId'] == family.householdId &&
            payload['name'] is String &&
            (payload['name'] as String).trim().isNotEmpty &&
            (payload['name'] as String).length <= 120 &&
            people is List &&
            people.length <= 64 &&
            people.every(
              (p) =>
                  p is Map &&
                  p.length == 2 &&
                  isResourceId(p['id'] as String? ?? '') &&
                  p['name'] is String &&
                  (p['name'] as String).length <= 120 &&
                  (p['name'] as String).trim().isNotEmpty,
            );
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  ({String entity, Map<String, int>? vector, String? payload})
  _recoveredCurrent(Map<String, Object?> row) {
    final payload = _recoveryPayload(row['payload_json']);
    final id = payload['id'] is String
        ? payload['id'] as String
        : row['resource_id'] as String;
    if ({
      'event_upserted',
      'event_deleted',
      'conflict_resolved',
      'retention_kept',
      'retention_deleted',
    }.contains(row['kind'])) {
      final events = database.raw.select(
        'SELECT e.*,v.vector_json FROM events e LEFT JOIN event_versions v ON v.event_id=e.id WHERE e.id=?',
        [id],
      );
      if (events.isNotEmpty) {
        return (
          entity: id,
          vector: recoveryVector(events.single['vector_json']),
          payload: _eventFromRow(events.single).encode(),
        );
      }
      final removed = database.raw.select(
        'SELECT * FROM calendar_deletions WHERE event_id=?',
        [id],
      );
      return (
        entity: id,
        vector: removed.isEmpty
            ? null
            : recoveryVector(removed.single['vector_json']),
        payload: removed.isEmpty
            ? null
            : jsonEncode(_deletionPayload(removed.single)),
      );
    }
    if (row['kind'] == 'child_created' || row['kind'] == 'child_updated') {
      final child = database.raw.select(
        'SELECT c.*,v.vector_json FROM children c LEFT JOIN child_profile_versions v ON v.child_id=c.id WHERE c.id=?',
        [id],
      );
      if (child.isEmpty) return (entity: id, vector: null, payload: null);
      final r = child.single;
      return (
        entity: id,
        vector: recoveryVector(r['vector_json']),
        payload: jsonEncode({
          'id': id,
          'householdId': r['household_id'],
          'name': r['display_name'],
          'colorArgb': r['color_argb'],
          'cloudAlias': r['cloud_alias'],
        }),
      );
    }
    if (row['kind'] == 'participant_upserted') {
      final people = database.raw.select(
        'SELECT * FROM participant_profiles WHERE id=?',
        [id],
      );
      if (people.isEmpty) return (entity: id, vector: null, payload: null);
      final r = people.single;
      return (
        entity: id,
        vector: recoveryVector(r['vector_json']),
        payload: jsonEncode({
          'id': id,
          'householdId': r['household_id'],
          'kind': r['kind'],
          'name': r['display_name'],
          'colorArgb': r['color_argb'],
          'adultId': r['adult_id'],
        }),
      );
    }
    final value = database.raw.select(
      'SELECT value FROM app_preferences WHERE key=?',
      ['household-vector-${load()!.householdId}'],
    );
    return (
      entity: id,
      vector: value.isEmpty ? null : recoveryVector(value.single['value']),
      payload: row['payload_json'] as String,
    );
  }

  void reconcileRecoveryIntents() {
    for (final row in database.raw.select(
      "SELECT * FROM recovery_intents WHERE status IN ('pending','queued')",
    )) {
      if (row['status'] == 'queued') {
        final uploaded = database.raw.select(
          "SELECT 1 FROM outbox WHERE operation_id=? AND state='uploaded'",
          [row['queued_operation_id']],
        );
        if (uploaded.isNotEmpty) {
          database.raw.execute(
            "UPDATE recovery_intents SET status='done',reason=NULL WHERE source_operation_id=?",
            [row['source_operation_id']],
          );
        }
        continue;
      }
      final current = _recoveredCurrent(Map<String, Object?>.from(row));
      final original = recoveryVector(row['vector_json']);
      if (current.vector != null &&
          original != null &&
          compareVectors(original, current.vector!) == VectorRelation.before) {
        database.raw.execute(
          "UPDATE recovery_intents SET status='done',reason='dominated_by_current_state' WHERE source_operation_id=?",
          [row['source_operation_id']],
        );
      }
    }
    // Receipts/applied IDs carry deduplication; completed intent needs no body.
    // This also handles intent dominated by a deletion received during catch-up.
    database.raw.execute("DELETE FROM recovery_intents WHERE status='done'");
  }

  List<RecoveredChange> recoveredChanges() => database.raw
      .select(
        "SELECT * FROM recovery_intents WHERE status!='done' ORDER BY source_operation_id",
      )
      .map((r) {
        final row = Map<String, Object?>.from(r);
        final current = _recoveredCurrent(row);
        final payload = _recoveryPayload(row['payload_json']);
        final label =
            (payload['title'] is String ? payload['title'] as String : null) ??
            (payload['name'] is String ? payload['name'] as String : null) ??
            (row['kind'] == 'retention_deleted'
                ? 'Removed appointment'
                : 'Family details');
        final fingerprint = jsonEncode([
          row['source_operation_id'],
          row['status'],
          current.vector,
          current.payload,
        ]);
        return RecoveredChange(
          row['source_operation_id'] as String,
          row['resource_id'] as String,
          row['kind'] as String,
          label,
          row['status'] as String,
          row['reason'] as String?,
          fingerprint,
        );
      })
      .toList();

  String queueRecoveredIntent(
    String id, {
    required String reviewedFingerprint,
  }) {
    if (recoveryState?['phase'] != 'review') {
      throw StateError('Finish recovery checks before review.');
    }
    final change = recoveredChanges().where((c) => c.id == id).firstOrNull;
    if (change == null ||
        change.status != 'pending' ||
        change.fingerprint != reviewedFingerprint) {
      throw StateError('This recovered change needs a fresh review.');
    }
    if (openConflicts().isNotEmpty || retentionConflicts().isNotEmpty) {
      throw StateError('Resolve recovered conflicts first.');
    }
    final row = Map<String, Object?>.from(
      database.raw.select(
        'SELECT * FROM recovery_intents WHERE source_operation_id=?',
        [id],
      ).single,
    );
    if (!_validRecoveryIntent(row)) {
      throw StateError('Unverified recovered change.');
    }
    final current = _recoveredCurrent(row);
    final original = recoveryVector(row['vector_json'])!;
    if (current.vector == null ||
        current.payload == null ||
        compareVectors(original, current.vector!) != VectorRelation.equal) {
      throw StateError('Recovered causality requires review.');
    }
    final vector = {...current.vector!};
    vector[deviceId] = (vector[deviceId] ?? 0) + 1;
    final op = newId();
    final kind = row['kind'] == 'child_created' ? 'child_updated' : row['kind'];
    database.transaction(() {
      var content = current.payload!;
      if ({
        'event_upserted',
        'event_deleted',
        'conflict_resolved',
        'retention_kept',
      }.contains(kind)) {
        final event =
            CalendarEvent.fromJson(
              Map<String, Object?>.from(jsonDecode(content) as Map),
            ).copyWith(
              revision: ((jsonDecode(content) as Map)['revision'] as int) + 1,
              updatedAt: DateTime.now().toUtc(),
            );
        _saveEventRows(event, vector: vector);
        content = event.encode();
        if (kind == 'retention_kept') {
          database.raw.execute(
            'UPDATE event_versions SET retention_keep_vector=? WHERE event_id=?',
            [jsonEncode(vector), current.entity],
          );
        }
      } else if (kind == 'retention_deleted') {
        final deletion = Map<String, Object?>.from(jsonDecode(content) as Map)
          ..['vector'] = vector;
        _removeRetainedContent(deletion);
        content = jsonEncode(deletion);
      } else if (kind == 'child_updated') {
        database.raw.execute(
          'INSERT OR REPLACE INTO child_profile_versions VALUES (?,?)',
          [current.entity, jsonEncode(vector)],
        );
      } else if (kind == 'participant_upserted') {
        database.raw.execute(
          'UPDATE participant_profiles SET vector_json=? WHERE id=?',
          [jsonEncode(vector), current.entity],
        );
      } else if (kind == 'household_shared') {
        database.raw.execute(
          'INSERT OR REPLACE INTO app_preferences VALUES (?,?)',
          ['household-vector-${load()!.householdId}', jsonEncode(vector)],
        );
      }
      database.raw.execute(
        'INSERT INTO outbox(operation_id,family_id,resource_id,kind,payload_json,vector_json,created_at) VALUES (?,?,?,?,?,?,?)',
        [
          op,
          row['family_id'],
          row['resource_id'],
          kind,
          content,
          jsonEncode(vector),
          DateTime.now().toUtc().toIso8601String(),
        ],
      );
      database.raw.execute(
        "UPDATE recovery_intents SET status='queued',queued_operation_id=?,reviewed_payload_json=?,reviewed_vector_json=? WHERE source_operation_id=?",
        [op, content, jsonEncode(vector), id],
      );
    });
    return op;
  }

  void trackReviewedRecoveryResolution() {
    if (!recoveryPending || recoveryState?['phase'] != 'review') return;
    for (final row in database.raw.select(
      "SELECT * FROM outbox WHERE state='pending' AND kind IN ('conflict_resolved','retention_kept','retention_deleted')",
    )) {
      if (database.raw.select(
        'SELECT 1 FROM recovery_intents WHERE queued_operation_id=?',
        [row['operation_id']],
      ).isNotEmpty) {
        continue;
      }
      database.raw.execute(
        'INSERT INTO recovery_intents(source_operation_id,family_id,resource_id,kind,payload_json,vector_json,status,queued_operation_id,reason) VALUES (?,?,?,?,?,?,?,?,?)',
        [
          newId(),
          row['family_id'],
          row['resource_id'],
          row['kind'],
          row['payload_json'],
          row['vector_json'],
          'queued',
          row['operation_id'],
          null,
        ],
      );
    }
  }

  void resumeRecoveredRetention() {
    if (recoveryState?['phase'] != 'review' ||
        recoveredChanges().isNotEmpty ||
        openConflicts().isNotEmpty ||
        retentionConflicts().isNotEmpty ||
        database.raw
            .select("SELECT 1 FROM outbox WHERE state='pending'")
            .isNotEmpty) {
      throw StateError(
        'Finish recovered changes and conflicts before resuming cleanup.',
      );
    }
    database.transaction(() {
      setRecoveryPhase('ready');
      database.raw.execute(
        "DELETE FROM app_preferences WHERE key='retention-recovery-pending'",
      );
    });
  }
}
