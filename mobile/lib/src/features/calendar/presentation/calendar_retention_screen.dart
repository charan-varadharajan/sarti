import 'dart:convert';

import 'package:flutter/material.dart';

import '../domain/calendar_event.dart';
import '../domain/calendar_retention.dart';
import 'calendar_controller.dart';
import '../data/calendar_repository.dart';

class CalendarRetentionScreen extends StatefulWidget {
  const CalendarRetentionScreen({super.key, required this.controller});
  final CalendarController controller;
  @override
  State<CalendarRetentionScreen> createState() =>
      _CalendarRetentionScreenState();
}

class _CalendarRetentionScreenState extends State<CalendarRetentionScreen> {
  CalendarRetention? _selected;
  bool _saving = false;
  String? _message;

  Future<void> _save() async {
    final controller = widget.controller;
    final householdId = controller.family?.householdId;
    final policy = controller.repository.retentionPolicy;
    if (policy == null ||
        policy['can_manage'] != true ||
        _saving ||
        controller.updateRetention == null) {
      return;
    }
    final period =
        _selected ??
        CalendarRetention.values.byName(policy['period'] as String);
    final count = controller.repository
        .retentionCandidates(period, controller.clock())
        .length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apply family calendar retention?'),
        content: Text(
          period == CalendarRetention.never
              ? 'Keep calendar history. This stops future cleanup; it cannot restore entries already removed.'
              : 'Remove completed appointments after ${period.label.toLowerCase()} across family phones. '
                    '$count entries on this phone meet the age rule; pending edits and conflicts are deferred. '
                    'Future appointments and active recurring series stay. Each adult’s phone applies this to their private entries. '
                    'Existing backups and exports may still contain older history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apply to family'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (controller.family?.householdId != householdId) {
      setState(
        () => _message = 'Household changed. Reopen retention settings.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await controller.updateRetention!(period, policy['revision'] as int);
      if (mounted) {
        setState(() {
          _selected = null;
          _message = 'Family calendar retention updated.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Could not update retention. Sync to refresh the policy and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final repository = widget.controller.repository;
      final policy = repository.retentionPolicy;
      final canManage =
          policy?['can_manage'] == true &&
          widget.controller.updateRetention != null;
      final selected =
          _selected ??
          CalendarRetention.values.byName(
            policy?['period'] as String? ?? 'week',
          );
      final recoveryPending = repository.retentionPaused;
      return Scaffold(
        appBar: AppBar(title: const Text('Calendar retention')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'One setting for the family',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const Text(
              'Family calendar admins choose how long completed appointments stay on family phones. '
              'Private appointments remain private; each adult’s phone handles its own cleanup.',
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<CalendarRetention>(
              initialValue: selected,
              decoration: const InputDecoration(
                labelText: 'Keep completed appointments for',
              ),
              items: [
                for (final value in CalendarRetention.values)
                  DropdownMenuItem(value: value, child: Text(value.label)),
              ],
              onChanged: canManage && !_saving
                  ? (value) => setState(() => _selected = value)
                  : null,
            ),
            const SizedBox(height: 12),
            Text(
              policy == null
                  ? 'Connect and sync with Sarti to load the family policy.'
                  : policy['enabled'] != true
                  ? 'Default: 1 week. An admin must apply the policy before existing history is removed.'
                  : 'Active family policy: ${CalendarRetention.values.byName(policy['period'] as String).label}.',
            ),
            if (!canManage && policy != null)
              const Text(
                'Only the family owner or an explicitly authorized calendar admin can change this.',
              ),
            if (recoveryPending)
              const Text(
                'Cleanup is paused on this restored family while safe recovery synchronization remains unverified.',
              ),
            if (canManage)
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Applying…' : 'Review and apply'),
              ),
            const SizedBox(height: 16),
            const Text(
              'Future appointments and active recurring series stay. Cleanup waits for sync and preserves pending edits and unresolved conflicts. '
              'Phones catch up when they reconnect; deletion may be delayed while the app is inactive. '
              'Existing encrypted backups and exports are separate and may contain older entries.',
            ),
            if (_message != null) Text(_message!),
            for (final row in repository.retentionConflicts()) _conflict(row),
          ],
        ),
      );
    },
  );

  Widget _conflict(Map<String, Object?> row) {
    final controller = widget.controller;
    final event = CalendarEvent.fromJson(
      Map<String, Object?>.from(jsonDecode(row['event_json'] as String) as Map),
    );
    final access = controller.repository.database.raw.select(
      'SELECT value FROM app_preferences WHERE key=?',
      ['family-access-${event.householdId}'],
    );
    final role = access.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(access.single['value'] as String) as Map;
    final canResolve =
        event.calendarResourceId == controller.repository.personalResourceId ||
        role['role'] == 'owner' ||
        {'write', 'admin'}.contains(role['permission']);
    void resolve(bool keep) {
      try {
        controller.resolveHistory(
          event.id,
          keep: keep,
          reviewedVector: row['review_vector_json'] as String,
        );
      } catch (_) {
        setState(
          () => _message =
              'This appointment changed. Sync and review its latest version.',
        );
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Retention conflict: ${event.title}'),
            const Text(
              'An edit conflicts with automatic deletion. Neither choice is applied silently.',
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: canResolve ? () => resolve(true) : null,
                  child: const Text('Keep appointment'),
                ),
                TextButton(
                  onPressed: canResolve ? () => resolve(false) : null,
                  child: const Text('Delete appointment'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
