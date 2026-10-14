import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium.dart';
import 'package:sarti_mobile/src/core/auth/native_passkey_adapter.dart';
import 'package:sarti_mobile/src/core/crypto/device_key_store.dart';
import 'package:sarti_mobile/src/core/crypto/resource_crypto.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/core/ids.dart';
import 'package:sarti_mobile/src/core/network/sarti_api.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/features/backup/backup_recovery.dart';
import 'package:sarti_mobile/src/features/backup/family_recovery_coordinator.dart';
import 'package:sarti_mobile/src/features/sync/resource_key_sync.dart';
import 'package:sarti_mobile/src/features/sync/sync_engine.dart';

class _HttpRecoverySecrets implements SecretStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    values.clear();
  }
}

/// RECOVERY-HTTP-001 extends the existing real HTTP/PostgreSQL host. WebAuthn
/// remains its explicit stub; device keys, grants, SQLCipher and relay are real.
Future<void> familyRecoveryHttpJourney({
  required Sodium sodium,
  required SartiApiClient originalApi,
  required CalendarRepository originalRepository,
  required DeviceKeyMaterial originalKeys,
  required NativePasskeyAdapter credential,
  required String baseUrl,
}) async {
  const phrase =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
  final family = originalRepository.load()!;
  final original = family.events.single;
  originalRepository.saveEvent(
    original.copyWith(
      title: 'Recovered pending HTTP edit',
      revision: original.revision + 1,
    ),
  );
  final blob = await BackupRecovery.snapshot(
    database: originalRepository.database,
    key: originalKeys.databaseKey.extractBytes(),
    phrase: phrase,
    sodium: sodium,
    familyId: family.householdId,
  );
  await originalApi.uploadBackup(family.householdId, blob, 0);
  final box = sodium.crypto.box.keyPair(), sign = sodium.crypto.sign.keyPair();
  final keys = DeviceKeyMaterial(
    databaseKey: sodium.secureRandom(32),
    encryptionPublicKey: box.publicKey,
    encryptionSecretKey: box.secretKey,
    signingPublicKey: sign.publicKey,
    signingSecretKey: sign.secretKey,
    deviceId: newId(),
  );
  final api = SartiApiClient(Uri.parse(baseUrl));
  final folder = Directory.systemTemp.createTempSync('sarti-recovery-http-');
  var target = SartiDatabase.open(
    '${folder.path}/replacement.db',
    keys.databaseKey.extractBytes(),
  );
  FamilyRecoveryCoordinator? coordinator;
  try {
    final session = await api.authenticatePasskey(credential, keys);
    expect(session.deviceId, isNot(originalRepository.deviceId));
    await expectLater(
      originalApi.download(family.householdId, 0),
      throwsA(
        isA<SartiApiException>().having(
          (e) => e.statusCode,
          'revoked old session',
          401,
        ),
      ),
    );
    final downloaded = await api.downloadBackup(family.householdId);
    expect(downloaded!.bytes, blob);
    final secrets = _HttpRecoverySecrets()
      ..values['sign-secret-v1'] = 'fresh-http-fixture-secret';
    await BackupRecovery.stage(
      blob: downloaded.bytes,
      phrase: phrase,
      familyId: family.householdId,
      current: target,
      sodium: sodium,
      secrets: secrets,
    );
    final path = target.path;
    target.close();
    await BackupRecovery.activate(path, secrets);
    final key = base64Url.decode(secrets.values['database-key-v1']!);
    target = SartiDatabase.open(path, key);
    key.fillRange(0, key.length, 0);
    final repository = CalendarRepository(
      target,
      deviceId: session.deviceId,
      adultId: session.adultId,
    );
    final engine = SyncEngine(
      database: target,
      repository: repository,
      crypto: ResourceCrypto(sodium),
      sodium: sodium,
      relay: api,
      deviceId: session.deviceId,
    );
    final directory = ResourceKeySync(
      database: target,
      repository: repository,
      sodium: sodium,
      keys: keys,
      deviceId: session.deviceId,
      api: api,
    );
    coordinator = FamilyRecoveryCoordinator(
      repository: repository,
      listFamilies: api.listFamilies,
      prepareKeys: () =>
          directory.prepare(family.householdId, recoveryOnly: true),
      sync: (downloadOnly) =>
          engine.synchronize(family.householdId, downloadOnly: downloadOnly),
      readPolicy: () => api.calendarRetention(family.householdId),
      onChanged: () {},
    );
    await coordinator.synchronize();
    expect(
      repository.load()!.events.single.title,
      'Recovered pending HTTP edit',
    );
    expect(coordinator.changes, hasLength(1));
    expect(target.resourceKey(family.calendarResourceId, 1), isNotNull);
    final current = (await api.listFamilies())
        .singleWhere((f) => f.id == family.householdId)
        .resources
        .singleWhere((r) => r.id == family.calendarResourceId);
    expect(current.keyEpoch, greaterThan(1));
    expect(target.resourceKey(current.id, current.keyEpoch), isNotNull);
    await coordinator.approve(coordinator.changes.single);
    expect(coordinator.changes, isEmpty);
    final delivered = (await api.download(
      family.householdId,
      0,
    )).operations.where((e) => e.authorDeviceId == session.deviceId).toList();
    expect(delivered, hasLength(1));
    expect(delivered.single.keyEpoch, current.keyEpoch);
    expect(delivered.single.logicalVersion[session.deviceId], 1);
    await coordinator.resumeCleanup(coordinator.historyFingerprint);
    expect(repository.recoveryPending, isFalse);
    expect(secrets.values['sign-secret-v1'], 'fresh-http-fixture-secret');
  } finally {
    coordinator?.dispose();
    target.close();
    api.close();
    keys.dispose();
    folder.deleteSync(recursive: true);
  }
}
