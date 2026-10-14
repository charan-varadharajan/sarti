import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/network/sarti_api.dart';
import '../calendar/data/calendar_repository.dart';
import '../calendar/domain/calendar_retention.dart';
import '../sync/sync_engine.dart';

/// Current server authority is separate from historical snapshot keys/content.
class FamilyRecoveryCoordinator extends ChangeNotifier {
  FamilyRecoveryCoordinator({
    required this.repository,
    required this.listFamilies,
    required this.prepareKeys,
    required this.sync,
    required this.readPolicy,
    required this.onChanged,
    this.provisionResource,
    this.newResourceKey,
    this.clock = DateTime.now,
    this.afterPublish,
  });
  final CalendarRepository repository;
  final Future<List<RemoteFamily>> Function() listFamilies;
  final Future<void> Function() prepareKeys;
  final Future<SyncReport> Function(bool downloadOnly) sync;
  final Future<Map<String, dynamic>> Function() readPolicy;
  final Future<RemoteResource> Function(String id, String kind, bool share)?
  provisionResource;
  final Uint8List Function()? newResourceKey;
  final Future<void> Function()? afterPublish;
  final VoidCallback onChanged;
  final DateTime Function() clock;
  RemoteFamily? _family;
  bool _disposed = false;
  Future<SyncReport>? _active;
  bool get busy => _active != null;
  Map<String, Object?>? get state => repository.recoveryState;
  List<RecoveredChange> get changes => repository.recoveredChanges();
  void _changed() {
    if (!_disposed) {
      onChanged();
      notifyListeners();
    }
  }

  Future<void> _authorize() async {
    final local =
        repository.load() ?? (throw StateError('No restored family.'));
    final families = await listFamilies();
    if (_disposed) throw StateError('Recovery is closed.');
    final matches = families
        .where(
          (f) =>
              f.id == local.householdId &&
              f.status == 'active' &&
              f.role == 'owner',
        )
        .toList();
    if (matches.length != 1) {
      throw StateError('Active family-owner authorization is required.');
    }
    _family = matches.single;
    repository.database.raw.execute(
      'INSERT OR REPLACE INTO app_preferences VALUES (?,?)',
      [
        'family-access-${local.householdId}',
        jsonEncode({'role': 'owner', 'permission': 'admin'}),
      ],
    );
  }

  RemoteResource _writable(String id) {
    final resource = _family?.resources
        .where((r) => r.id == id && r.kind != 'personal_calendar')
        .firstOrNull;
    if (resource == null ||
        (resource.permission != null && resource.permission != 'admin')) {
      throw StateError('Current resource authority is unavailable.');
    }
    final keys = repository.database.raw.select(
      'SELECT MAX(key_epoch) AS epoch FROM resource_keys WHERE resource_id=?',
      [id],
    );
    if (keys.single['epoch'] != resource.keyEpoch ||
        repository.database.resourceKey(id, resource.keyEpoch) == null) {
      throw StateError('Wait for a verified current resource key.');
    }
    return resource;
  }

  Future<SyncReport> synchronize() {
    if (_active != null) return _active!;
    final operation = _synchronize();
    _active = operation;
    return operation.whenComplete(() {
      _active = null;
      _changed();
    });
  }

  Future<SyncReport> _synchronize() async {
    var uploaded = 0, applied = 0, conflicts = 0;
    try {
      await _authorize();
      if (state?['phase'] == 'blocked') {
        throw StateError(
          'This snapshot lacks verified history; keep it read-only.',
        );
      }
      repository.setRecoveryPhase('catching_up');
      _changed();
      await prepareKeys();
      final family = repository.load()!.householdId;
      var caught = false;
      for (var page = 0; page < 100; page++) {
        final before = repository.database.raw.select(
          'SELECT server_cursor FROM sync_state WHERE family_id=?',
          [family],
        );
        final cursor = before.isEmpty ? 0 : before.single['server_cursor'];
        final report = await sync(true);
        applied += report.applied;
        conflicts += report.conflicts;
        final after = repository.database.raw.select(
          'SELECT server_cursor FROM sync_state WHERE family_id=?',
          [family],
        ).single['server_cursor'];
        if (cursor == after) {
          caught = true;
          break;
        }
      }
      if (!caught) {
        throw StateError('Available updates are not fully processed.');
      }
      repository.reconcileRecoveryIntents();
      repository.setRecoveryPhase('review');
      final queued = repository.database.raw.select(
        "SELECT * FROM outbox WHERE state='pending'",
      );
      for (final row in queued) {
        _writable(row['resource_id'] as String);
        if (row['family_id'] != family ||
            repository.database.raw.select(
              "SELECT 1 FROM recovery_intents WHERE queued_operation_id=? AND status='queued' AND COALESCE(reviewed_payload_json,payload_json)=? AND COALESCE(reviewed_vector_json,vector_json)=? AND family_id=? AND resource_id=? AND (kind=? OR (kind='child_created' AND ?='child_updated'))",
              [
                row['operation_id'],
                row['payload_json'],
                row['vector_json'],
                row['family_id'],
                row['resource_id'],
                row['kind'],
                row['kind'],
              ],
            ).isEmpty) {
          throw StateError('Outgoing work requires recovery review.');
        }
      }
      if (queued.isNotEmpty) {
        final report = await sync(false);
        uploaded += report.uploaded;
        applied += report.applied;
        conflicts += report.conflicts;
        repository.reconcileRecoveryIntents();
      }
      final policy = await readPolicy();
      repository.cacheRetentionPolicy(policy);
      return SyncReport(
        uploaded: uploaded,
        applied: applied,
        conflicts: conflicts,
      );
    } catch (_) {
      if (!_disposed && state?['phase'] != 'blocked') {
        repository.setRecoveryPhase('paused', reason: 'checks_incomplete');
      }
      rethrow;
    } finally {
      _changed();
    }
  }

  Future<void> approve(RecoveredChange reviewed) async {
    await synchronize();
    await _authorize();
    _writable(reviewed.resourceId);
    repository.queueRecoveredIntent(
      reviewed.id,
      reviewedFingerprint: reviewed.fingerprint,
    );
    _changed();
    await synchronize();
    await afterPublish?.call();
  }

  Future<void> authorizeResource(
    RecoveredChange reviewed, {
    required bool share,
  }) async {
    await synchronize();
    await _authorize();
    final current = changes.where((c) => c.id == reviewed.id).firstOrNull;
    if (state?['phase'] != 'review' ||
        current == null ||
        current.fingerprint != reviewed.fingerprint ||
        current.status != 'pending' ||
        !{'child_created', 'participant_upserted'}.contains(current.kind) ||
        _family!.resources.any((r) => r.id == current.resourceId) ||
        provisionResource == null ||
        newResourceKey == null) {
      throw StateError('This resource requires a fresh review.');
    }
    final kind = current.kind == 'child_created'
        ? 'child_profile'
        : 'participant_profile';
    final candidate = newResourceKey!();
    try {
      // Persist before provisioning; retries retain the same unpublished key.
      if (repository.database.resourceKey(current.resourceId, 1) == null) {
        repository.database.setResourceKey(current.resourceId, 1, candidate);
      }
      final resource = await provisionResource!(
        current.resourceId,
        kind,
        share,
      );
      if (resource.id != current.resourceId ||
          resource.kind != kind ||
          resource.keyEpoch != 1) {
        throw StateError('Unexpected restored resource identity.');
      }
      if (kind == 'child_profile') {
        repository.database.raw.execute(
          'INSERT INTO child_sync(child_id,key_epoch,share_with_calendar_guardians) VALUES (?,0,?) ON CONFLICT(child_id) DO UPDATE SET share_with_calendar_guardians=excluded.share_with_calendar_guardians',
          [current.resourceId, share ? 1 : 0],
        );
      }
      await synchronize();
    } finally {
      candidate.fillRange(0, candidate.length, 0);
    }
  }

  Future<void> resolveEvent(
    String conflictId, {
    required bool useRemote,
    required String reviewedFingerprint,
  }) async {
    await synchronize();
    await _authorize();
    final rows = repository.database.raw.select(
      "SELECT * FROM conflicts WHERE id=? AND status='open'",
      [conflictId],
    );
    if (rows.isEmpty ||
        _conflictFingerprint(rows.single) != reviewedFingerprint ||
        state?['phase'] != 'review') {
      throw StateError('Review the latest conflict.');
    }
    _writable(rows.single['resource_id'] as String);
    repository.resolveConflict(conflictId, useRemote: useRemote);
    _changed();
    await synchronize();
    await afterPublish?.call();
  }

  String conflictFingerprint(String id) {
    final rows = repository.database.raw.select(
      "SELECT * FROM conflicts WHERE id=? AND status='open'",
      [id],
    );
    return rows.isEmpty ? '' : _conflictFingerprint(rows.single);
  }

  String _conflictFingerprint(dynamic row) => jsonEncode([
    row['id'],
    row['local_payload_json'],
    row['remote_payload_json'],
    row['local_vector_json'],
    row['remote_vector_json'],
  ]);

  Future<void> resolveRetention(
    String id, {
    required bool keep,
    required String reviewedVector,
  }) async {
    await synchronize();
    await _authorize();
    final row = repository
        .retentionConflicts()
        .where((r) => r['event_id'] == id)
        .firstOrNull;
    if (row == null || state?['phase'] != 'review') {
      throw StateError('Review the latest retention conflict.');
    }
    _writable(row['resource_id'] as String);
    repository.resolveRetentionConflict(
      id,
      keep: keep,
      reviewedVector: reviewedVector,
    );
    _changed();
    await synchronize();
    await afterPublish?.call();
  }

  String get historyFingerprint {
    final policy = repository.retentionPolicy;
    final events = repository.database.raw
        .select(
          'SELECT e.id,v.vector_json FROM events e LEFT JOIN event_versions v ON v.event_id=e.id ORDER BY e.id',
        )
        .map((r) => [r['id'], r['vector_json']])
        .toList();
    return jsonEncode([policy, events, state?['snapshot_at']]);
  }

  int get expiringCount {
    final policy = repository.retentionPolicy;
    return policy == null
        ? 0
        : repository
              .retentionCandidates(
                CalendarRetention.values.byName(policy['period'] as String),
                clock(),
              )
              .length;
  }

  bool get canResume =>
      state?['phase'] == 'review' &&
      changes.isEmpty &&
      repository.openConflicts().isEmpty &&
      repository.retentionConflicts().isEmpty;

  Future<void> resumeCleanup(String reviewedFingerprint) async {
    await synchronize();
    await _authorize();
    if (!canResume || historyFingerprint != reviewedFingerprint) {
      throw StateError('Recovered history changed; review it again.');
    }
    repository.resumeRecoveredRetention();
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
