import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/features/guardians/invitation_links.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_controller.dart';
import 'package:sodium/sodium.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import 'support/guardian_fixture.dart';

void main() {
  late Sodium sodium;
  setUpAll(() async {
    sodium = await SodiumInit.init();
    tz_data.initializeTimeZones();
  });
  test('GUARD-SEC-001 invitation links reject foreign URLs, routes, queries and malformed tokens', () {
    final token = List.filled(43, 'x').join();
    expect(invitationToken(invitationLink(token)), token);
    expect(invitationToken('  $token  '), token);
    for (final bad in [
      'https://evil.example/#$token',
      'sarti://invite/path#$token',
      'sarti://invite?token=$token',
      'sarti://user@invite#$token',
      'sarti://invite:123#$token',
      'sarti://other#$token',
      'short',
      'sarti://invite#${token}extra',
    ]) {
      expect(() => invitationToken(bad), throwsFormatException);
    }
    expect(
      guardianVerificationCode(guardianKeyDigest(Uint8List(32), Uint8List(32)))
          .length,
      19,
    );
  });
  test('GUARD-SYNC-001 approval hands off retained current state, with restricted child profiles', () async {
    final g = GuardianFixture(sodium);
    addTearDown(g.close);
    final mia = g.f.a.repository.addChild(
      'Mia',
      0xff00ff00,
      cloudAlias: 'green-fox-1234',
    );
    final private = g.f.a.repository.addChild(
      'Jithu',
      0xff0000ff,
      cloudAlias: 'blue-fox-1234',
    );
    CalendarController(g.f.a.repository, timezone: 'America/Vancouver').save(
      title: 'Swimming',
      localStart: DateTime(2026, 10, 13, 9),
      durationMinutes: 120,
      childIds: [mia.id, private.id],
    );
    await g.owner.refresh();
    await g.owner.create();
    await g.guardian.accept(invitationLink(g.token));
    expect(g.status, 'pending');
    expect(g.f.b.database.resourceKey(g.f.calendarId, 1), isNull);
    expect(await g.f.b.keyGrants(), isEmpty);
    g.f.operations.clear(); // Relay expired; device-local content remains.
    await g.owner.refresh();
    final permissions = {
      g.f.calendarId: 'read',
      g.profileId: 'read',
      mia.id: 'read',
    };
    await g.owner.approve(g.review, permissions, 'Dad');
    expect(g.owner.message, contains('encrypted calendar'));
    await g.guardian.refresh();
    expect(g.guardian.ready, isTrue);
    final family = g.f.b.repository.load()!;
    expect(family.children.map((c) => c.name), ['Mia']);
    expect(family.events.single.title, 'Swimming');
    expect(family.events.single.durationMinutes, 120);
    expect(family.events.single.childIds.toSet(), {mia.id, private.id});
    expect(family.guardians.map((p) => p.name), contains('Dad'));
    expect(g.f.b.database.resourceKey(private.id, 1), isNull);
    expect(g.f.operations.every((op) => op.ciphertext.isNotEmpty), isTrue);
    final marker = g.f.b.database.raw.select(
      'SELECT operation_id, applied_at FROM applied_operations WHERE operation_id=?',
      [g.f.operations.last.operationId],
    );
    expect(marker, hasLength(1));
    expect(DateTime.tryParse(marker.single['applied_at'] as String), isNotNull);
    await g.guardian.refresh();
    expect(g.guardian.ready, isTrue);
    expect(
      g.f.b.repository.load()!.guardians.map((p) => p.name),
      unorderedEquals(['Me', 'Dad']),
    );
    expect(g.f.a.repository.load()!.events.single.revision, 1);
  });
  test('GUARD-SYNC-002 lost approval response resumes once; removal excludes future keys', () async {
    final g = GuardianFixture(sodium);
    addTearDown(g.close);
    await g.owner.refresh();
    await g.owner.create();
    await g.guardian.accept(g.token);
    final permissions = {g.f.calendarId: 'write', g.profileId: 'read'};
    g.loseApprovalResponse = true;
    final review = g.review;
    await g.owner.approve(review, permissions, 'Parent');
    expect(g.status, 'approved');
    expect(g.owner.message, contains('did not finish'));
    await g.owner.approve(review, permissions, 'Parent');
    await g.guardian.refresh();
    expect(g.guardian.ready, isTrue);
    final count = g.f.operations.length;
    await g.owner.approve(g.review, permissions, 'Parent');
    expect(g.f.operations, hasLength(count));
    await g.owner.revoke(g.review);
    expect(g.f.b.database.resourceKey(g.f.calendarId, 2), isNull);
    expect(
      g.f.grants
          .where((grant) => grant.keyEpoch == 2)
          .any((grant) => grant.recipientDeviceId == g.f.b.id),
      isFalse,
    );
  });
  test(
    'GUARD-SEC-002 malformed family profiles cannot alter local state',
    () async {
      final g = GuardianFixture(sodium);
      addTearDown(g.close);
      await g.owner.refresh();
      final before = g.f.a.repository.load()!.name;
      expect(
        () => g.f.a.repository.applySharedHousehold(
          operationId: 'bad',
          familyId: g.f.familyId,
          resourceId: g.f.calendarId,
          vector: {g.f.a.id: 1},
          payload: {
            'householdId': g.f.familyId,
            'name': 'Forged',
            'guardians': [],
          },
        ),
        throwsStateError,
      );
      expect(
        () => g.f.a.repository.applySharedHousehold(
          operationId: 'bad',
          familyId: g.f.familyId,
          resourceId: g.profileId,
          vector: {g.f.a.id: 1},
          payload: {
            'householdId': g.f.familyId,
            'name': 'Forged',
            'guardians': [
              {'id': 'invalid', 'name': 'Private'},
            ],
          },
        ),
        throwsStateError,
      );
      expect(g.f.a.repository.load()!.name, before);
      expect(
        g.f.a.database.raw.select('SELECT * FROM applied_operations'),
        isEmpty,
      );
    },
  );
  test('GUARD-SYNC-003 orphaned recovery progress permits an explicit fresh handoff', () async {
    final g = GuardianFixture(sodium);
    addTearDown(g.close);
    await g.owner.refresh();
    await g.owner.create();
    await g.guardian.accept(g.token);
    final access = {g.f.calendarId: 'read', g.profileId: 'read'};
    await g.owner.approve(g.review, access, 'Parent');
    await g.guardian.refresh();
    final count = g.f.operations.length;
    g.f.a.database.raw.execute(
      'DELETE FROM outbox',
    ); // Prepared old-identity clearing.
    await g.owner.approve(g.review, access, 'Parent');
    expect(g.f.operations.length, greaterThan(count));
    await g.guardian.refresh();
    expect(g.guardian.ready, isTrue);
    expect(
      g.f.b.repository.load()!.guardians.where((p) => p.name == 'Parent'),
      hasLength(1),
    );
  });
}
