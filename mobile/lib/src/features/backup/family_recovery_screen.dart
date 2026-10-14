import 'dart:convert';

import 'package:flutter/material.dart';

import '../calendar/data/calendar_repository.dart';
import '../calendar/domain/calendar_event.dart';
import '../calendar/domain/calendar_retention.dart';
import 'family_recovery_coordinator.dart';

class FamilyRecoveryScreen extends StatefulWidget {
  const FamilyRecoveryScreen({super.key, required this.coordinator});
  final FamilyRecoveryCoordinator coordinator;
  @override
  State<FamilyRecoveryScreen> createState() => _FamilyRecoveryScreenState();
}

class _FamilyRecoveryScreenState extends State<FamilyRecoveryScreen> {
  bool _busy = false;
  String? _message;
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Recovery needs attention. Keep this calendar and retry after connecting, or use an authorized backup with verified history.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resume() async {
    final c = widget.coordinator;
    final reviewed = c.historyFingerprint;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resume this calendar?'),
        content: Text(
          '${c.expiringCount} entries on this phone meet the family retention age rule. '
          'Future entries and active recurring series stay. Available updates have been processed, but changes that expired from the seven-day relay may be unavailable. '
          'Review this restored history before resuming normal edits and cleanup.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep paused'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Resume calendar and cleanup'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _run(() => c.resumeCleanup(reviewed));
    }
  }

  Future<void> _resource(RecoveredChange change) async {
    var share = false;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Authorize this recovered profile?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(change.title),
              const Text(
                'This profile has no current resource. Creating it requires a new permission check; an already deleted resource cannot be restored this way.',
              ),
              CheckboxListTile(
                value: share,
                onChanged: (v) => setDialog(() => share = v ?? false),
                title: const Text('Share with current calendar guardians'),
                subtitle: const Text(
                  'Off by default. This grants read access to the existing authorized calendar guardians.',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Authorize profile'),
            ),
          ],
        ),
      ),
    );
    if (approved == true && mounted) {
      await _run(
        () => widget.coordinator.authorizeResource(change, share: share),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.coordinator,
    builder: (context, _) {
      final c = widget.coordinator;
      final review = c.state?['phase'] == 'review';
      final enabled = review && !_busy && !c.busy;
      return Scaffold(
        appBar: AppBar(title: const Text('Recovered changes')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Your restored calendar is preserved',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const Text(
              'Old phone credentials are not restored. Confirm access, process available updates, and review unsent changes before normal edits and automatic cleanup resume.',
            ),
            Text(
              c.state?['snapshot_at'] == null
                  ? 'Snapshot time unavailable.'
                  : 'Snapshot time: ${DateTime.tryParse(c.state!['snapshot_at'] as String)?.toLocal() ?? 'Unavailable'}',
            ),
            Text(
              c.repository.retentionPolicy == null
                  ? 'Family retention policy not yet verified.'
                  : 'Family retention policy: ${CalendarRetention.values.byName(c.repository.retentionPolicy!['period'] as String).label}.',
            ),
            const Text(
              'The server keeps encrypted sync messages for seven days. A restored snapshot may not include changes that have already expired. This screen does not establish that all household data is up to date.',
            ),
            Text(
              c.state?['phase'] == 'blocked'
                  ? 'This snapshot needs verified causal history. It stays read-only; obtain an appropriate authorized snapshot.'
                  : review
                  ? 'Available updates processed. Review recovered changes below.'
                  : 'Recovery checks are paused or in progress. Calendar history remains readable.',
            ),
            OutlinedButton(
              onPressed: _busy || c.busy
                  ? null
                  : () => _run(() async {
                      await c.synchronize();
                    }),
              child: const Text('Check access and available updates'),
            ),
            if (_message != null) Text(_message!),
            for (final change in c.changes)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(change.title),
                      Text(
                        change.kind == 'retention_deleted' ||
                                change.kind == 'event_deleted'
                            ? 'Recovered deletion request'
                            : 'Recovered unsent change',
                      ),
                      if (change.status == 'quarantined')
                        const Text(
                          'Unverified change retained offline. It cannot be published automatically.',
                        ),
                      if (change.status == 'queued')
                        const Text(
                          'Reviewed change awaiting authorized delivery.',
                        ),
                      if (change.status == 'pending')
                        Wrap(
                          spacing: 8,
                          children: [
                            FilledButton(
                              onPressed: enabled
                                  ? () => _run(() => c.approve(change))
                                  : null,
                              child: const Text('Approve recovered change'),
                            ),
                            if ({
                              'child_created',
                              'participant_upserted',
                            }.contains(change.kind))
                              TextButton(
                                onPressed: enabled
                                    ? () => _resource(change)
                                    : null,
                                child: const Text(
                                  'Review profile authorization',
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            for (final conflict in c.repository.openConflicts())
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Choose between conflicting changes'),
                      Text('Restored: ${conflict.local.title}'),
                      Text('Incoming: ${conflict.remote.title}'),
                      Builder(
                        builder: (context) {
                          final fingerprint = c.conflictFingerprint(
                            conflict.id,
                          );
                          return Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: enabled
                                    ? () => _run(
                                        () => c.resolveEvent(
                                          conflict.id,
                                          useRemote: false,
                                          reviewedFingerprint: fingerprint,
                                        ),
                                      )
                                    : null,
                                child: const Text('Keep restored version'),
                              ),
                              TextButton(
                                onPressed: enabled
                                    ? () => _run(
                                        () => c.resolveEvent(
                                          conflict.id,
                                          useRemote: true,
                                          reviewedFingerprint: fingerprint,
                                        ),
                                      )
                                    : null,
                                child: const Text('Use incoming version'),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            for (final row in c.repository.retentionConflicts())
              Builder(
                builder: (context) {
                  final event = CalendarEvent.fromJson(
                    Map<String, Object?>.from(
                      jsonDecode(row['event_json'] as String) as Map,
                    ),
                  );
                  final vector = row['review_vector_json'] as String;
                  return Card(
                    child: Column(
                      children: [
                        Text('Deletion conflict: ${event.title}'),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: enabled
                                  ? () => _run(
                                      () => c.resolveRetention(
                                        event.id,
                                        keep: true,
                                        reviewedVector: vector,
                                      ),
                                    )
                                  : null,
                              child: const Text('Keep appointment'),
                            ),
                            TextButton(
                              onPressed: enabled
                                  ? () => _run(
                                      () => c.resolveRetention(
                                        event.id,
                                        keep: false,
                                        reviewedVector: vector,
                                      ),
                                    )
                                  : null,
                              child: const Text('Approve deletion'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            if (c.changes.isEmpty &&
                c.repository.openConflicts().isEmpty &&
                c.repository.retentionConflicts().isEmpty &&
                review)
              const Text('No recovered changes require approval.'),
            FilledButton(
              onPressed: enabled && c.canResume ? _resume : null,
              child: const Text('Review history and resume cleanup'),
            ),
          ],
        ),
      );
    },
  );
}
