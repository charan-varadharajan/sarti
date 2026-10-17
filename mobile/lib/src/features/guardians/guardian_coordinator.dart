import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sarti_mobile/src/core/crypto/device_key_store.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/core/network/sarti_api.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';

import 'invitation_links.dart';

class GuardianCoordinator extends ChangeNotifier {
  GuardianCoordinator({
    required this.database,
    required this.repository,
    required this.api,
    required this.keys,
    required this.synchronize,
    this.onLocalChanged,
    this.joining = false,
  });
  final bool joining;
  final SartiDatabase database;
  final CalendarRepository repository;
  final GuardianApi api;
  final DeviceKeyMaterial keys;
  final Future<void> Function() synchronize;
  final VoidCallback? onLocalChanged;
  List<RemoteFamily> families = [];
  List<GuardianReview> invitations = [];
  GuardianInvitation? invitation;
  bool busy = false;
  String? message;
  bool _disposed = false;

  RemoteFamily? get family {
    if (joining) {
      final pending = database.raw.select(
        "SELECT value FROM app_preferences WHERE key='joining-household'",
      );
      return pending.isEmpty
          ? null
          : families.where((f) => f.id == pending.single['value']).firstOrNull;
    }
    final local = repository.load();
    if (local != null) {
      return families.where((f) => f.id == local.householdId).firstOrNull;
    }
    return families.length == 1 ? families.single : null;
  }

  bool get isOwner =>
      !joining &&
      repository.load() != null &&
      family?.role == 'owner' &&
      family?.status == 'active';
  bool get ready =>
      isOwner ||
      (family != null &&
          database.raw.select('SELECT 1 FROM app_preferences WHERE key=?', [
            'guardian-ready-${family!.id}',
          ]).isNotEmpty);
  String get ownCode => guardianVerificationCode(
    guardianKeyDigest(keys.signingPublicKey, keys.encryptionPublicKey),
  );

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _run(Future<void> Function() work) async {
    if (busy || _disposed) return;
    busy = true;
    message = null;
    _changed();
    try {
      await work();
    } on FormatException {
      message = 'Enter a valid Sarti invitation link or code.';
    } on SartiApiException catch (error) {
      message = switch (error.statusCode) {
        401 => 'Sign in again to manage guardians.',
        403 || 404 => 'This invitation or access is unavailable.',
        409 => 'The invitation or device changed. Refresh and review it again.',
        _ => 'Could not connect. Your calendar remains safe; try again.',
      };
    } catch (_) {
      message = 'Sharing did not finish. Try again; pending encrypted changes are retained.';
    } finally {
      busy = false;
      _changed();
    }
  }

  Future<void> refresh() => _run(_refresh);

  Future<void> _refresh() async {
    final refreshed = await api.listFamilies();
    if (_disposed) return;
    families = refreshed;
    final pending = database.raw.select(
      "SELECT value FROM app_preferences WHERE key='joining-household'",
    );
    final candidate = pending.isNotEmpty
        ? families.where((f) => f.id == pending.single['value']).firstOrNull
        : repository.load() == null && families.length == 1
        ? families.single
        : null;
    if (candidate != null &&
        candidate.status == 'active' &&
        candidate.role == 'guardian') {
      final calendar = candidate.resources
          .where((r) => r.kind == 'calendar')
          .single;
      if (!{'read', 'write', 'admin'}.contains(calendar.permission)) {
        throw StateError('Calendar permission is missing.');
      }
      database.transaction(() {
        if (database.raw.select('SELECT 1 FROM households WHERE id=?', [
          candidate.id,
        ]).isEmpty) {
          database.raw.execute(
            'INSERT INTO households(id,display_name,created_at,calendar_resource_id) VALUES (?,?,?,?)',
            [
              candidate.id,
              'Family calendar',
              DateTime.now().toUtc().toIso8601String(),
              calendar.id,
            ],
          );
          database.raw.execute(
            'INSERT INTO sync_state(family_id,server_cursor) VALUES (?,?)',
            [candidate.id, candidate.syncStartCursor],
          );
        }
        if (joining) repository.selectHousehold(candidate.id);
      });
    }
    // Refresh every known household's authority, never reuse the visible one's.
    for (final local in repository.localFamilies()) {
      final remote = families
          .where((f) => f.id == local.householdId && f.status == 'active')
          .firstOrNull;
      final previous = database.raw.select(
        'SELECT value FROM app_preferences WHERE key=?',
        ['family-access-${local.householdId}'],
      );
      if (remote != null) {
        final calendar = remote.resources
            .where((r) => r.kind == 'calendar')
            .firstOrNull;
        database.raw.execute(
          'INSERT OR REPLACE INTO app_preferences VALUES (?,?)',
          [
            'family-access-${local.householdId}',
            jsonEncode({
              'role': remote.role,
              'permission': calendar?.permission,
            }),
          ],
        );
      } else if (previous.isNotEmpty) {
        database.raw.execute(
          'INSERT OR REPLACE INTO app_preferences VALUES (?,?)',
          [
            'family-access-${local.householdId}',
            jsonEncode({'role': 'revoked', 'permission': null}),
          ],
        );
      }
    }
    onLocalChanged?.call();
    if (family?.status == 'active') {
      await synchronize();
      onLocalChanged?.call();
    }
    invitations = isOwner ? await api.listInvitations(family!.id) : [];
    final current = invitation;
    if (current != null &&
        (!current.expiresAt.isAfter(DateTime.now().toUtc()) ||
            invitations.any(
              (i) =>
                  i.id == current.id &&
                  (i.status != 'open' ||
                      !i.expiresAt.isAfter(DateTime.now().toUtc())),
            ))) {
      invitation = null;
    }
  }

  Future<RemoteFamily> _owner() async {
    final expectedId = repository.load()?.householdId;
    await synchronize(); // Provision/drain offline writes before taking a baseline.
    families = await api.listFamilies();
    if (repository.load()?.householdId != expectedId || !isOwner) {
      throw StateError('Only the family owner can invite guardians.');
    }
    return family!;
  }

  Future<void> create() => _run(() async {
    final owner = await _owner();
    invitation = await api.createInvitation(owner.id);
    await _refresh();
  });

  Future<void> accept(String input) => _run(() async {
    if (repository.load() != null && !joining) {
      throw StateError('Use Join another household to accept this invitation.');
    }
    final id = await api.acceptInvitation(invitationToken(input));
    database.raw.execute(
      "INSERT OR REPLACE INTO app_preferences VALUES ('joining-household',?)",
      [id],
    );
    InvitationLinks.token.value = null;
    await _refresh();
    message = 'Invitation accepted. Compare your code with the owner and wait for approval.';
  });

  Future<void> approve(
    GuardianReview review,
    Map<String, String> permissions,
    String name,
  ) => _run(() async {
    final owner = await _owner();
    if (repository.load()!.openConflicts != 0) {
      message = 'Resolve open calendar conflicts before approving a guardian.';
      return;
    }
    if (review.adultId == null ||
        review.deviceId == null ||
        review.signingPublicKey == null ||
        review.encryptionPublicKey == null ||
        name.trim().isEmpty ||
        name.length > 120) {
      throw StateError('Review the guardian first.');
    }
    final digest = guardianKeyDigest(
      review.signingPublicKey!,
      review.encryptionPublicKey!,
    );
    await api.approveInvitation(owner.id, review, permissions, digest);
    await synchronize(); // Receive concurrent changes, issue current-epoch grants.
    final profile = owner.resources.singleWhere(
      (r) => r.kind == 'family_profile',
    );
    repository.queueGuardianHandoff(
      invitationId: review.id,
      profileResourceId: profile.id,
      childResourceIds: permissions.keys
          .where(
            (id) => owner.resources.any(
              (r) => r.id == id && r.kind == 'child_profile',
            ),
          )
          .toSet(),
      participantResourceIds: permissions.keys
          .where(
            (id) => owner.resources.any(
              (r) => r.id == id && r.kind == 'participant_profile',
            ),
          )
          .toSet(),
      guardianId: review.adultId!,
      guardianName: name,
    );
    onLocalChanged?.call();
    await synchronize();
    await _refresh();
    message = 'Guardian approved. The encrypted calendar has been shared.';
  });

  Future<void> cancel(GuardianReview review) => _run(() async {
    final owner = await _owner();
    await api.cancelInvitation(owner.id, review.id);
    if (invitation?.id == review.id) invitation = null;
    await _refresh();
  });

  Future<void> revoke(GuardianReview review) => _run(() async {
    final owner = await _owner();
    if (review.adultId == null) throw StateError('Missing guardian.');
    await api.revokeGuardian(owner.id, review.adultId!);
    await synchronize(); // Rotate current epochs; revoked devices receive no keys.
    await _refresh();
    message = 'Guardian removed. Future updates use fresh encryption keys.';
  });

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
