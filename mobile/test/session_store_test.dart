import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/core/auth/session_store.dart';
import 'package:sarti_mobile/src/core/crypto/device_key_store.dart';
import 'package:sarti_mobile/src/core/network/sarti_api.dart';

void main() {
  test('session round-trips through protected storage', () async {
    final secrets = _MemorySecrets();
    final store = SessionStore(secrets);
    final session = AuthenticatedSession(
      adultId: 'adult',
      deviceId: 'device',
      token: 'secret-token',
      expiresAt: DateTime.utc(2026, 2),
    );

    await store.save(session);
    final loaded = await store.load(now: DateTime.utc(2026));

    expect(loaded?.adultId, session.adultId);
    expect(loaded?.deviceId, session.deviceId);
    expect(loaded?.token, session.token);
    expect(loaded?.expiresAt, session.expiresAt);
    expect(await store.lastDeviceId(), session.deviceId);
  });

  test(
    'expired or malformed sessions are deleted without deleting keys',
    () async {
      final secrets = _MemorySecrets()..values['device-key'] = 'keep';
      final store = SessionStore(secrets);
      await store.save(
        AuthenticatedSession(
          adultId: 'adult',
          deviceId: 'device',
          token: 'token',
          expiresAt: DateTime.utc(2026),
        ),
      );

      expect(await store.load(now: DateTime.utc(2026, 1, 2)), isNull);
      expect(await store.lastDeviceId(), 'device');
      expect(secrets.values['device-key'], 'keep');
      expect(secrets.deleteAllCalled, isFalse);

      secrets.values['authenticated-session-v1'] = '{bad json';
      expect(await store.load(), isNull);
      expect(secrets.values['device-key'], 'keep');
    },
  );
}

class _MemorySecrets implements SecretStore {
  final values = <String, String>{};
  bool deleteAllCalled = false;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<void> deleteAll() async {
    deleteAllCalled = true;
    values.clear();
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
