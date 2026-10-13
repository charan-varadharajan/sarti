import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sarti_mobile/src/core/network/sarti_api.dart';

import 'guardian_coordinator.dart';
import 'invitation_links.dart';

typedef InvitationCopier = Future<void> Function(String link);

Future<void> copyGuardianInvitation(String link) =>
    Clipboard.setData(ClipboardData(text: link));

typedef InvitationSharer = Future<void> Function(String link, Rect origin);

Future<void> shareGuardianInvitation(String link, Rect origin) async {
  await SharePlus.instance.share(
    ShareParams(
      text: 'Join my Sarti family: $link',
      sharePositionOrigin: origin,
    ),
  );
}

class GuardianScreen extends StatefulWidget {
  const GuardianScreen({
    super.key,
    required this.coordinator,
    this.initialInvitation,
    this.share = shareGuardianInvitation,
    this.copy = copyGuardianInvitation,
    this.onOpenCalendar,
  });
  final GuardianCoordinator coordinator;
  final String? initialInvitation;
  final InvitationSharer share;
  final InvitationCopier copy;
  final VoidCallback? onOpenCalendar;
  @override
  State<GuardianScreen> createState() => _GuardianScreenState();
}

class _GuardianScreenState extends State<GuardianScreen> {
  late final TextEditingController _input = TextEditingController(
    text: widget.initialInvitation,
  );
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _approve(GuardianReview review) async {
    final c = widget.coordinator;
    final resources = c.family!.resources;
    final family = c.repository.load()!;
    final choices = review.status == 'approved'
        ? Map<String, String>.from(review.permissions)
        : <String, String>{
            for (final r in resources)
              if (r.kind != 'child_profile' ||
                  family.children.any((child) => child.id == r.id))
                r.id: r.kind == 'calendar' ? 'write' : 'read',
          };
    final name = TextEditingController(
      text: family.guardians
          .where((g) => g.id == review.adultId)
          .firstOrNull
          ?.name,
    );
    var verified = false;
    final code = guardianVerificationCode(
      guardianKeyDigest(review.signingPublicKey!, review.encryptionPublicKey!),
    );
    final approved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              MediaQuery.viewInsetsOf(context).bottom + 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Review guardian access',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Text(
                    'Compare this verification code on both phones before approving.',
                  ),
                  SelectableText(code, key: const Key('guardian-review-code')),
                  TextField(
                    key: const Key('guardian-name'),
                    controller: name,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: 'Name on your calendar',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const Text(
                    'They can see the family name and guardian profiles. Choose calendar and child access below.',
                  ),
                  for (final resource in resources)
                    if (resource.kind == 'calendar')
                      DropdownButtonFormField<String>(
                        initialValue: choices[resource.id],
                        decoration: const InputDecoration(
                          labelText: 'Calendar access',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'read',
                            child: Text('View calendar'),
                          ),
                          DropdownMenuItem(
                            value: 'write',
                            child: Text('View and edit calendar'),
                          ),
                        ],
                        onChanged: review.status == 'approved'
                            ? null
                            : (v) => setState(() => choices[resource.id] = v!),
                      ),
                  for (final child in family.children)
                    if (resources.any((r) => r.id == child.id))
                      CheckboxListTile(
                        title: Text('Share ${child.name}\u2019s profile'),
                        value: choices.containsKey(child.id),
                        onChanged: review.status == 'approved'
                            ? null
                            : (v) => setState(() {
                                if (v == true) {
                                  choices[child.id] = 'read';
                                } else {
                                  choices.remove(child.id);
                                }
                              }),
                      ),
                  CheckboxListTile(
                    key: const Key('guardian-code-confirmation'),
                    title: const Text(
                      'The codes match and I recognize this guardian',
                    ),
                    value: verified,
                    onChanged: (v) => setState(() => verified = v == true),
                  ),
                  FilledButton(
                    key: const Key('guardian-approve'),
                    onPressed: verified && name.text.trim().isNotEmpty
                        ? () => Navigator.pop(context, true)
                        : null,
                    child: const Text('Approve and share encrypted calendar'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final guardianName = name.text.trim();
    // Dispose after the closing route animation has released its text field.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    name.dispose();
    if (approved == true && mounted) {
      await c.approve(review, choices, guardianName);
    }
  }

  Future<void> _remove(GuardianReview review) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove guardian?'),
        content: const Text(
          'They will not receive future updates. Copies already on their phone cannot be erased.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (approved == true && mounted) await widget.coordinator.revoke(review);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.coordinator,
    builder: (context, _) {
      final c = widget.coordinator;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Family guardians'),
          actions: [
            IconButton(
              tooltip: 'Refresh guardian status',
              onPressed: c.busy ? null : c.refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (c.busy) const LinearProgressIndicator(),
              if (c.message case final message?)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(message, key: const Key('guardian-message')),
                ),
              if (c.isOwner) ...[
                const Text(
                  'Invite another guardian using text, email or another app. They sign in, accept and wait for your approval.',
                ),
                FilledButton.icon(
                  key: const Key('guardian-create-invitation'),
                  onPressed: c.busy ? null : c.create,
                  icon: const Icon(Icons.person_add),
                  label: const Text('Create invitation'),
                ),
                if (c.invitation case final invitation?)
                  _InvitationCard(
                    invitation: invitation,
                    share: widget.share,
                    copy: widget.copy,
                  ),
                for (final review in c.invitations)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            review.memberStatus == 'revoked'
                                ? 'Guardian removed'
                                : switch (review.status) {
                                    'open' => 'Invitation ready',
                                    'pending' => 'Awaiting your approval',
                                    'approved' => 'Approved guardian',
                                    _ => 'Invitation cancelled',
                                  },
                          ),
                          if (review.status != 'approved')
                            Text(
                              'Expires ${MaterialLocalizations.of(context).formatShortDate(review.expiresAt.toLocal())} ${TimeOfDay.fromDateTime(review.expiresAt.toLocal()).format(context)}',
                            ),
                          if ((review.status == 'pending' &&
                                      review.expiresAt.isAfter(
                                        DateTime.now().toUtc(),
                                      ) ||
                                  review.status == 'approved') &&
                              review.memberStatus != 'revoked' &&
                              review.deviceId != null)
                            FilledButton.tonal(
                              onPressed: c.busy ? null : () => _approve(review),
                              child: Text(
                                review.status == 'approved'
                                    ? 'Finish or retry encrypted sharing'
                                    : 'Review and approve',
                              ),
                            ),
                          if (review.status == 'open' ||
                              review.status == 'pending')
                            TextButton(
                              onPressed: c.busy ? null : () => c.cancel(review),
                              child: const Text('Cancel invitation'),
                            ),
                          if (review.status == 'approved' &&
                              review.memberStatus == 'active')
                            TextButton(
                              onPressed: c.busy ? null : () => _remove(review),
                              child: const Text('Remove guardian'),
                            ),
                        ],
                      ),
                    ),
                  ),
              ] else ...[
                if (c.repository.load() == null &&
                    c.family?.status != 'pending' &&
                    c.family?.role != 'owner') ...[
                  const Text(
                    'Open an invitation link, scan the owner\u2019s QR with your camera, or paste it here. Sarti must be installed to open the link.',
                  ),
                  TextField(
                    key: const Key('guardian-invitation-input'),
                    controller: _input,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Invitation link or code',
                    ),
                  ),
                  FilledButton(
                    key: const Key('guardian-accept'),
                    onPressed: c.busy ? null : () => c.accept(_input.text),
                    child: const Text('Accept invitation'),
                  ),
                ],
                if (c.family?.role == 'owner' && c.repository.load() == null)
                  const Text(
                    'Restore your encrypted family before managing guardians.',
                  ),
                if (c.family?.status == 'pending') ...[
                  const Text(
                    'Waiting for the owner\u2019s approval. Compare this code with them:',
                  ),
                  SelectableText(
                    c.ownCode,
                    key: const Key('guardian-own-code'),
                  ),
                ],
                if (c.family?.status == 'active' && !c.ready)
                  const Text(
                    'Waiting for the owner to finish encrypted sharing. Refresh when they are ready.',
                  ),
                if (c.ready && c.family?.status == 'active')
                  FilledButton(
                    onPressed: widget.onOpenCalendar,
                    child: const Text('Open family calendar'),
                  ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: c.busy ? null : c.refresh,
                  child: const Text('Refresh status'),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _InvitationCard extends StatefulWidget {
  const _InvitationCard({
    required this.invitation,
    required this.share,
    required this.copy,
  });
  final GuardianInvitation invitation;
  final InvitationSharer share;
  final InvitationCopier copy;
  @override
  State<_InvitationCard> createState() => _InvitationCardState();
}

class _InvitationCardState extends State<_InvitationCard> {
  Timer? _expiry;
  String? _message;
  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant _InvitationCard old) {
    super.didUpdateWidget(old);
    if (old.invitation != widget.invitation) _schedule();
  }

  void _schedule() {
    _expiry?.cancel();
    final remaining = widget.invitation.expiresAt.difference(
      DateTime.now().toUtc(),
    );
    if (!remaining.isNegative) {
      _expiry = Timer(remaining, () => setState(() {}));
    }
  }

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.invitation.expiresAt.isAfter(DateTime.now().toUtc())) {
      return const Text('Invitation expired. Create a new one.');
    }
    final link = invitationLink(widget.invitation.token);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'Scan to join. Works once and expires in 48 hours. Owner approval is required.',
            ),
            QrImageView(
              key: const Key('guardian-invitation-qr'),
              data: link,
              size: 224,
              backgroundColor: Colors.white,
              semanticsLabel: 'Guardian invitation QR code',
            ),
            Wrap(
              spacing: 8,
              children: [
                Builder(
                  builder: (context) => FilledButton.tonalIcon(
                    key: const Key('guardian-share-link'),
                    onPressed: () async {
                      final box = context.findRenderObject() as RenderBox;
                      try {
                        await widget.share(
                          link,
                          box.localToGlobal(Offset.zero) & box.size,
                        );
                      } catch (_) {
                        if (mounted) {
                          setState(
                            () => _message =
                                'Sharing unavailable. Copy the link instead.',
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.share),
                    label: const Text('Share link'),
                  ),
                ),
                TextButton.icon(
                  key: const Key('guardian-copy-link'),
                  onPressed: () async {
                    try {
                      await widget.copy(link);
                      if (mounted) {
                        setState(
                          () => _message = 'Invitation link copied. Share it only with the intended guardian.',
                        );
                      }
                    } catch (_) {
                      if (mounted) {
                        setState(
                          () => _message =
                              'Copy unavailable. Try the share button instead.',
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy link'),
                ),
              ],
            ),
            if (_message case final message?) Text(message),
          ],
        ),
      ),
    );
  }
}
