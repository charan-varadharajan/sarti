import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium.dart';
import 'package:sarti_mobile/src/core/ids.dart';
import 'package:sarti_mobile/src/core/network/sarti_api.dart';

import 'support/child_sync_fixture.dart';

void main() {
  test('RECOVERY-KEY-001 recovery directory refresh excludes private keys and implicit child provisioning', () async {
    final f = ChildSyncFixture(await SodiumInit.init(), personal: true);
    try {
      final child = f.a.repository.addChild('Prepared child', 0xffccddff);
      final private = newId();
      f.resources[private] = RemoteResource(
        id: private,
        kind: 'personal_calendar',
        keyEpoch: 2,
        permission: 'admin',
      );
      f.privateOwners[private] = f.a.id;
      final count = f.a.database.raw.select('SELECT * FROM outbox').length;
      await f.a.keySync.prepare(f.familyId, recoveryOnly: true);
      expect(f.resources.containsKey(child.id), isFalse);
      expect(f.grants.where((g) => g.resourceId == private), isEmpty);
      expect(f.a.database.resourceKey(private, 2), isNull);
      expect(
        f.a.database.raw.select(
          "SELECT * FROM resource_catalog WHERE kind='personal_calendar'",
        ),
        isEmpty,
      );
      expect(
        f.a.database.raw.select('SELECT * FROM personal_calendars'),
        isEmpty,
      );
      expect(f.a.database.raw.select('SELECT * FROM outbox'), hasLength(count));
    } finally {
      f.close();
    }
  });
  test('RECOVERY-KEY-002 saved key cannot replace an established epoch without a current self grant', () async {
    final f = ChildSyncFixture(await SodiumInit.init());
    try {
      await f.a.keySync.prepare(f.familyId);
      f.grants.removeWhere((g) => g.recipientDeviceId == f.a.id);
      final count = f.grants.length;
      await expectLater(
        f.a.keySync.prepare(f.familyId, recoveryOnly: true),
        throwsStateError,
      );
      expect(f.grants, hasLength(count));
      expect(f.operations, isEmpty);
    } finally {
      f.close();
    }
  });
}
