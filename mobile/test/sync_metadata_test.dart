import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/core/crypto/resource_crypto.dart';
import 'package:sarti_mobile/src/features/sync/sync_engine.dart';
import 'package:sodium/sodium.dart';

import 'support/child_sync_fixture.dart';

Map<String, Object> metadata({int protocol = 2, bool reverse = false}) => {
  'protocol': protocol,
  'familyId': 'family',
  'resourceId': 'calendar',
  'keyEpoch': 1,
  'operationId': 'operation',
  'authorDeviceId': 'a',
  'deviceSequence': 1,
  'logicalVersion': reverse ? {'b': 2, 'a': 1} : {'a': 1, 'b': 2},
};

void main() {
  late Sodium sodium;
  setUpAll(() async => sodium = await SodiumInit.init());

  test('AAD-UNIT-001 protocol 2 has exact stable bytes regardless of map order', () {
    const expected =
        '{"protocol":2,"familyId":"family","resourceId":"calendar","keyEpoch":1,"operationId":"operation","authorDeviceId":"a","deviceSequence":1,"logicalVersion":{"a":1,"b":2}}';
    expect(utf8.decode(resourceAdditionalData(metadata())), expected);
    expect(
      resourceAdditionalData(metadata(reverse: true)),
      resourceAdditionalData(metadata()),
    );
    expect(
      resourceAdditionalData(
        Map.fromEntries(metadata().entries.toList().reversed),
      ),
      resourceAdditionalData(metadata()),
    );
    expect(
      utf8.decode(resourceAdditionalData(metadata(protocol: 1, reverse: true))),
      jsonEncode(metadata(protocol: 1, reverse: true)),
    );
    expect(
      resourceAdditionalData(metadata(protocol: 1, reverse: true)),
      isNot(resourceAdditionalData(metadata(protocol: 1))),
    );
  });

  test('AAD-SEC-001 all authenticated fields and protocol downgrade reject tampering', () {
    final crypto = ResourceCrypto(sodium);
    final key = crypto.newResourceKey();
    addTearDown(key.dispose);
    final original = metadata();
    final encrypted = crypto.encrypt(
      plaintext: Uint8List.fromList([7, 8]),
      key: key,
      metadata: original,
    );
    for (final field in original.keys) {
      final changed = Map<String, Object>.from(original);
      changed[field] = switch (field) {
        'protocol' => 1,
        'keyEpoch' || 'deviceSequence' => 2,
        'logicalVersion' => {'a': 1, 'b': 3},
        _ => 'changed',
      };
      expect(
        () => crypto.decrypt(
          EncryptedResourcePayload(
            nonce: encrypted.nonce,
            ciphertext: encrypted.ciphertext,
            additionalData: resourceAdditionalData(changed),
          ),
          key,
        ),
        throwsA(anything),
        reason: field,
      );
    }
    expect(
      () => resourceAdditionalData(metadata(protocol: 3)),
      throwsStateError,
    );
    expect(
      () => resourceAdditionalData({...original, 'extra': 1}),
      throwsStateError,
    );
  });

  test('AAD-SYNC-001 pending version-1 envelope retries exact bytes without relabeling', () async {
    final f = ChildSyncFixture(sodium);
    addTearDown(f.close);
    // Build an actual legacy outbox envelope before network submission.
    final row = f.a.database.raw.select('SELECT * FROM outbox').single;
    final m = <String, Object>{
      'protocol': 1,
      'familyId': f.familyId,
      'resourceId': f.calendarId,
      'keyEpoch': 1,
      'operationId': row['operation_id'] as String,
      'authorDeviceId': f.a.id,
      'deviceSequence': 1,
      'logicalVersion': Map<String, int>.from(
        jsonDecode(row['vector_json'] as String) as Map,
      ),
    };
    final key = SecureKey.fromList(
      sodium,
      f.a.database.resourceKey(f.calendarId, 1)!,
    );
    addTearDown(key.dispose);
    final encrypted = ResourceCrypto(sodium).encrypt(
      plaintext: Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'kind': row['kind'],
            'payload': jsonDecode(row['payload_json'] as String),
          }),
        ),
      ),
      key: key,
      metadata: m,
    );
    final legacy = {
      'operationId': row['operation_id'],
      'familyId': f.familyId,
      'resourceId': f.calendarId,
      'authorDeviceId': f.a.id,
      'deviceSequence': 1,
      'keyEpoch': 1,
      'logicalVersion': m['logicalVersion'],
      'nonce': base64UrlEncode(encrypted.nonce),
      'ciphertext': base64UrlEncode(encrypted.ciphertext),
      'contentDigest': base64UrlEncode(
        sha256.convert([...encrypted.nonce, ...encrypted.ciphertext]).bytes,
      ),
    };
    f.a.database.raw.execute('UPDATE outbox SET envelope_json = ?', [
      jsonEncode(legacy),
    ]);
    f.loseNextReceipt = true;
    await expectLater(f.a.engine.synchronize(f.familyId), throwsStateError);
    await f.a.engine.synchronize(f.familyId);
    expect(f.attempts, hasLength(2));
    expect(f.attempts.every((e) => e.protocolVersion == 1), isTrue);
    expect(f.attempts.last.ciphertext, orderedEquals(encrypted.ciphertext));
    expect(f.operations, hasLength(1));
    await f.a.keySync.prepare(f.familyId);
    await f.b.keySync.prepare(f.familyId);
    await f.b.engine.synchronize(
      f.familyId,
    ); // Legacy family envelope authenticates.
  });

  test('AAD-SEC-002 legacy reordered ciphertext stays unapplied with cursor intact', () async {
    final f = ChildSyncFixture(sodium);
    addTearDown(f.close);
    await f.a.keySync.prepare(f.familyId);
    await f.b.keySync.prepare(f.familyId);
    final m = <String, Object>{
      'protocol': 1,
      'familyId': f.familyId,
      'resourceId': f.calendarId,
      'keyEpoch': 1,
      'operationId': 'legacy',
      'authorDeviceId': f.a.id,
      'deviceSequence': 1,
      'logicalVersion': {f.a.id: 1, f.b.id: 1},
    };
    final key = SecureKey.fromList(
      sodium,
      f.a.database.resourceKey(f.calendarId, 1)!,
    );
    addTearDown(key.dispose);
    final encrypted = ResourceCrypto(sodium).encrypt(
      plaintext: Uint8List.fromList(
        utf8.encode(
          '{"kind":"family_created","payload":{"householdId":"${f.familyId}"}}',
        ),
      ),
      key: key,
      metadata: m,
    );
    final vector = Map<String, int>.from(m['logicalVersion']! as Map);
    f.injected = [
      RelayEnvelope(
        serverSequence: 1,
        operationId: 'legacy',
        familyId: f.familyId,
        resourceId: f.calendarId,
        authorDeviceId: f.a.id,
        deviceSequence: 1,
        keyEpoch: 1,
        logicalVersion: Map.fromEntries(vector.entries.toList().reversed),
        nonce: encrypted.nonce,
        ciphertext: encrypted.ciphertext,
        contentDigest: Uint8List.fromList(
          sha256.convert([...encrypted.nonce, ...encrypted.ciphertext]).bytes,
        ),
      ),
    ];
    await expectLater(f.b.engine.synchronize(f.familyId), throwsA(anything));
    expect(
      f.b.database.raw
          .select('SELECT server_cursor FROM sync_state')
          .single['server_cursor'],
      0,
    );
    expect(f.b.repository.load()!.events, isEmpty);
    expect(f.injected!.single.ciphertext, orderedEquals(encrypted.ciphertext));
  });
}
