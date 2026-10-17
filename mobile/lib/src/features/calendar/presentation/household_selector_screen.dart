import 'package:flutter/material.dart';

import 'calendar_controller.dart';
import 'family_setup_screen.dart';
import '../../sync/sync_engine.dart';

/// Switching changes local visibility; it never copies members, keys or events.
class HouseholdSelectorScreen extends StatelessWidget {
  const HouseholdSelectorScreen({
    super.key,
    required this.controller,
    this.onGuardians,
    this.onRecoverySetup,
    this.onReviewPending,
    this.onRestoreHousehold,
  });
  final Future<int> Function(String familyId, String fingerprint)?
  onReviewPending;
  final CalendarController controller;
  final VoidCallback? onGuardians, onRecoverySetup, onRestoreHousehold;

  Future<void> _reviewPending(BuildContext context, String familyId) async {
    final db = controller.repository.database;
    final rows = db.raw.select(
      "SELECT * FROM outbox WHERE family_id=? AND state='pending' ORDER BY operation_id",
      [familyId],
    );
    final fingerprint = pendingOperationFingerprint(db, familyId);
    String? error;
    var busy = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => PopScope(
          canPop: !busy,
          child: AlertDialog(
            title: const Text('Review interrupted synchronization'),
            content: Text(
              error ??
                  '${rows.length} pending changes will stay encrypted on this phone. Sarti checks the original server receipt and preserves the exact original upload. If access was removed, these changes are quarantined so other households can synchronize. They are never published automatically. An expired receipt cannot prove whether a change arrived.',
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        setState(() {
                          busy = true;
                          error = null;
                        });
                        try {
                          await onReviewPending!(familyId, fingerprint);
                          if (context.mounted) Navigator.pop(context);
                        } catch (_) {
                          if (context.mounted) {
                            setState(() {
                              busy = false;
                              error = 'Could not reconcile. If access remains available, retry the original upload. Otherwise refresh your access and review again. No pending changes were discarded.';
                            });
                          }
                        }
                      },
                child: Text(
                  busy
                      ? 'Checking receipt…'
                      : 'Preserve and resume other households',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    controller.refresh();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Households')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Each household has its own calendar, people and permissions.',
          ),
          for (final family in controller.repository.localFamilies()) ...[
            ListTile(
              key: Key('select-household-${family.householdId}'),
              title: Text(family.name),
              selected: controller.family?.householdId == family.householdId,
              trailing: controller.family?.householdId == family.householdId
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                controller.selectHousehold(family.householdId);
                Navigator.pop(context);
              },
            ),
            if (onReviewPending != null &&
                controller.repository.database.raw.select(
                  "SELECT 1 FROM outbox WHERE family_id=? AND state='pending' AND envelope_json IS NOT NULL",
                  [family.householdId],
                ).isNotEmpty)
              TextButton(
                key: Key('review-pending-${family.householdId}'),
                onPressed: () => _reviewPending(context, family.householdId),
                child: const Text('Review interrupted synchronization'),
              ),
            if (controller.repository.database.raw.select(
              "SELECT 1 FROM recovery_intents WHERE family_id=? AND status='quarantined' AND reason='lost_write_authority'",
              [family.householdId],
            ).isNotEmpty)
              const Text(
                'Pending changes are preserved here and will not be sent automatically.',
              ),
          ],
          OutlinedButton.icon(
            key: const Key('create-additional-household'),
            icon: const Icon(Icons.add_home_outlined),
            label: const Text('Create household'),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => FamilySetupScreen(
                    controller: controller,
                    allowAdditional: true,
                    onRecoverySetup: onRecoverySetup,
                  ),
                ),
              );
              if (context.mounted) Navigator.pop(context);
            },
          ),
          if (onRestoreHousehold != null)
            TextButton.icon(
              key: const Key('restore-additional-household'),
              onPressed: onRestoreHousehold,
              icon: const Icon(Icons.restore),
              label: const Text('Restore another household'),
            ),
          if (onGuardians != null)
            TextButton.icon(
              key: const Key('join-additional-household'),
              icon: const Icon(Icons.mail_outline),
              label: const Text('Join another household'),
              onPressed: onGuardians,
            ),
        ],
      ),
    ),
  );
}
