import 'package:sarti_mobile/src/core/ids.dart';
import 'package:sarti_mobile/src/core/network/sarti_api.dart';
import 'package:sarti_mobile/src/core/crypto/resource_crypto.dart';
import 'package:sarti_mobile/src/features/guardians/guardian_coordinator.dart';
import 'package:sarti_mobile/src/features/guardians/invitation_links.dart';
import 'package:sarti_mobile/src/features/sync/sync_engine.dart';
import 'package:sodium/sodium.dart';

import 'child_sync_fixture.dart';

class GuardianFixture {
  GuardianFixture(Sodium sodium) : f = ChildSyncFixture(sodium) {
    profileId = newId();
    f.resources[profileId] = RemoteResource(
      id: profileId,
      kind: 'family_profile',
      keyEpoch: 1,
    );
    f.b.database.raw.execute('DELETE FROM households');
    f.denied.add(f.b.id);
    ownerApi = FixtureGuardianApi(this, true);
    guardianApi = FixtureGuardianApi(this, false);
    owner = GuardianCoordinator(
      database: f.a.database,
      repository: f.a.repository,
      api: ownerApi,
      keys: f.a.keys,
      synchronize: () async {
        await f.a.sync();
      },
    );
    f.b.engine = SyncEngine(
      database: f.b.database,
      repository: f.b.repository,
      crypto: ResourceCrypto(sodium),
      sodium: sodium,
      relay: _GuardianRelay(this),
      deviceId: f.b.id,
    );
    guardian = GuardianCoordinator(
      database: f.b.database,
      repository: f.b.repository,
      api: guardianApi,
      keys: f.b.keys,
      synchronize: () async {
        await f.b.keySync.prepare(f.familyId);
        await f.b.engine.synchronize(f.familyId);
      },
    );
  }
  final ChildSyncFixture f;
  late final String profileId;
  late final FixtureGuardianApi ownerApi, guardianApi;
  late final GuardianCoordinator owner, guardian;
  final token = List.filled(43, 'x').join();
  final invitationId = newId();
  String status = 'absent';
  DateTime expires = DateTime.now().toUtc().add(const Duration(hours: 48));
  int floor = 0, acceptCalls = 0, approveCalls = 0;
  bool loseApprovalResponse = false;
  Map<String, String> permissions = {};
  GuardianReview get review => GuardianReview(
    id: invitationId,
    status: status,
    expiresAt: expires,
    adultId: f.b.id,
    deviceId: f.b.id,
    signingPublicKey: f.b.keys.signingPublicKey,
    encryptionPublicKey: f.b.keys.encryptionPublicKey,
    memberStatus: status == 'approved'
        ? 'active'
        : status == 'revoked'
        ? 'revoked'
        : 'pending',
    permissions: permissions,
  );
  void close() {
    owner.dispose();
    guardian.dispose();
    f.close();
  }
}

class FixtureGuardianApi implements GuardianApi {
  FixtureGuardianApi(this.g, this.isOwner);
  final GuardianFixture g;
  final bool isOwner;
  @override
  Future<List<RemoteFamily>> listFamilies() async => isOwner
      ? [
          RemoteFamily(
            id: g.f.familyId,
            role: 'owner',
            status: 'active',
            resources: g.f.resources.values
                .map(
                  (r) => RemoteResource(
                    id: r.id,
                    kind: r.kind,
                    keyEpoch: r.keyEpoch,
                    permission: 'admin',
                  ),
                )
                .toList(),
          ),
        ]
      : g.status == 'pending' || g.status == 'approved'
      ? [
          RemoteFamily(
            id: g.f.familyId,
            role: 'guardian',
            status: g.status == 'approved' ? 'active' : 'pending',
            syncStartCursor: g.floor,
            resources: g.status == 'approved'
                ? g.f.resources.values
                      .where((r) => g.permissions.containsKey(r.id))
                      .map(
                        (r) => RemoteResource(
                          id: r.id,
                          kind: r.kind,
                          keyEpoch: r.keyEpoch,
                          permission: g.permissions[r.id],
                        ),
                      )
                      .toList()
                : [],
          ),
        ]
      : [];
  @override
  Future<GuardianInvitation> createInvitation(String familyId) async {
    if (!isOwner) throw const SartiApiException(403);
    g.status = 'open';
    return GuardianInvitation(g.invitationId, g.token, g.expires);
  }

  @override
  Future<List<GuardianReview>> listInvitations(String familyId) async =>
      g.status == 'absent' ? [] : [g.review];
  @override
  Future<String> acceptInvitation(String token) async {
    g.acceptCalls++;
    if (token != g.token ||
        g.status != 'open' ||
        !g.expires.isAfter(DateTime.now().toUtc())) {
      throw const SartiApiException(404);
    }
    g.status = 'pending';
    return g.f.familyId;
  }

  @override
  Future<void> approveInvitation(
    String familyId,
    GuardianReview review,
    Map<String, String> permissions,
    String digest,
  ) async {
    g.approveCalls++;
    if (!isOwner ||
        !{'pending', 'approved'}.contains(g.status) ||
        review.deviceId != g.f.b.id ||
        digest !=
            guardianKeyDigest(
              g.f.b.keys.signingPublicKey,
              g.f.b.keys.encryptionPublicKey,
            )) {
      throw const SartiApiException(409);
    }
    if (g.status == 'approved' &&
        (g.permissions.length != permissions.length ||
            !g.permissions.entries.every(
              (e) => permissions[e.key] == e.value,
            ))) {
      throw const SartiApiException(409);
    }
    if (g.status == 'pending') {
      g.status = 'approved';
      g.permissions = Map.from(permissions);
      g.floor = g.f.nextServerSequence;
      g.f.denied.remove(g.f.b.id);
      g.f.calendarGuardianPermission = permissions[g.f.calendarId]!;
      for (final e in permissions.entries.where(
        (e) => e.key != g.f.calendarId,
      )) {
        g.f.childPermissions[e.key] = e.value;
      }
    }
    if (g.loseApprovalResponse) {
      g.loseApprovalResponse = false;
      throw StateError('Prepared lost approval response.');
    }
  }

  @override
  Future<void> cancelInvitation(String familyId, String invitationId) async {
    g.status = 'revoked';
  }

  @override
  Future<void> revokeGuardian(String familyId, String adultId) async {
    g.status = 'revoked';
    g.f.denied.add(g.f.b.id);
    for (final resource in g.f.resources.values.toList()) {
      g.f.resources[resource.id] = RemoteResource(
        id: resource.id,
        kind: resource.kind,
        keyEpoch: resource.keyEpoch + 1,
      );
    }
  }
}

class _GuardianRelay implements EncryptedRelay {
  _GuardianRelay(this.g);
  final GuardianFixture g;
  @override
  Future<void> upload(RelayEnvelope envelope) async {
    if (g.status != 'approved' ||
        !{'write', 'admin'}.contains(g.permissions[envelope.resourceId])) {
      throw const SartiApiException(403);
    }
    await g.f.b.upload(envelope);
  }

  @override
  Future<RelayPage> download(String familyId, int cursor) async {
    if (g.status != 'approved') throw const SartiApiException(403);
    final page = await g.f.b.download(
      familyId,
      cursor < g.floor ? g.floor : cursor,
    );
    return RelayPage(
      page.operations
          .where((e) => g.permissions.containsKey(e.resourceId))
          .toList(),
      page.nextCursor,
    );
  }
}
