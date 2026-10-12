import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:sarti_mobile/src/core/ids.dart';
import 'package:sodium/sodium.dart';

abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<void> deleteAll();
}

abstract interface class DeviceUnlock {
  Future<bool> unlock();
}

class PlatformDeviceUnlock implements DeviceUnlock {
  PlatformDeviceUnlock([LocalAuthentication? authentication])
    : _authentication = authentication ?? LocalAuthentication();

  final LocalAuthentication _authentication;

  @override
  Future<bool> unlock() => _authentication.authenticate(
    localizedReason: 'Unlock your family calendar',
    sensitiveTransaction: true,
    persistAcrossBackgrounding: true,
  );
}

class PlatformSecretStore implements SecretStore {
  PlatformSecretStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _ios = IOSOptions(
    accessibility: KeychainAccessibility.passcode,
    synchronizable: false,
    accessControlFlags: [AccessControlFlag.userPresence],
  );
  static const _android = AndroidOptions.biometric(
    enforceBiometrics: true,
    // The app performs an explicit local_auth check above. Keep the protected
    // storage key cached for this process so loading the six-part device key
    // does not open overlapping authentication prompts.
    requireBiometricsPerOperation: false,
    storageNamespace: 'sarti_device_secrets',
  );

  @override
  Future<String?> read(String key) =>
      _storage.read(key: key, iOptions: _ios, aOptions: _android);

  @override
  Future<void> write(String key, String value) => _storage.write(
    key: key,
    value: value,
    iOptions: _ios,
    aOptions: _android,
  );

  @override
  Future<void> delete(String key) =>
      _storage.delete(key: key, iOptions: _ios, aOptions: _android);

  @override
  Future<void> deleteAll() =>
      _storage.deleteAll(iOptions: _ios, aOptions: _android);
}

class DeviceKeyMaterial {
  DeviceKeyMaterial({
    required this.databaseKey,
    required this.encryptionPublicKey,
    required this.encryptionSecretKey,
    required this.signingPublicKey,
    required this.signingSecretKey,
    required this.deviceId,
  });

  final SecureKey databaseKey;
  final Uint8List encryptionPublicKey;
  final SecureKey encryptionSecretKey;
  final Uint8List signingPublicKey;
  final SecureKey signingSecretKey;
  final String deviceId;

  void dispose() {
    databaseKey.dispose();
    encryptionSecretKey.dispose();
    signingSecretKey.dispose();
  }
}

class DeviceKeyStore {
  DeviceKeyStore(this.sodium, this.secrets, this.unlocker);

  final Sodium sodium;
  final SecretStore secrets;
  final DeviceUnlock unlocker;

  static const _databaseKey = 'database-key-v1';
  static const _boxPublic = 'box-public-v1';
  static const _boxSecret = 'box-secret-v1';
  static const _signPublic = 'sign-public-v1';
  static const _signSecret = 'sign-secret-v1';
  static const _deviceId = 'device-id-v1';

  Future<DeviceKeyMaterial> loadOrCreate() async {
    if (!await unlocker.unlock()) {
      throw StateError('Device authentication was cancelled.');
    }
    final storedDatabaseKey = await secrets.read(_databaseKey);
    if (storedDatabaseKey == null) return _create();
    final values = await Future.wait([
      secrets.read(_boxPublic),
      secrets.read(_boxSecret),
      secrets.read(_signPublic),
      secrets.read(_signSecret),
      secrets.read(_deviceId),
    ]);
    if (values.any((value) => value == null)) {
      throw StateError('Device key material is incomplete.');
    }
    return DeviceKeyMaterial(
      databaseKey: SecureKey.fromList(
        sodium,
        base64Url.decode(storedDatabaseKey),
      ),
      encryptionPublicKey: base64Url.decode(values[0]!),
      encryptionSecretKey: SecureKey.fromList(
        sodium,
        base64Url.decode(values[1]!),
      ),
      signingPublicKey: base64Url.decode(values[2]!),
      signingSecretKey: SecureKey.fromList(
        sodium,
        base64Url.decode(values[3]!),
      ),
      deviceId: values[4]!,
    );
  }

  Future<DeviceKeyMaterial> _create() async {
    final databaseKey = sodium.secureRandom(32);
    final encryption = sodium.crypto.box.keyPair();
    final signing = sodium.crypto.sign.keyPair();
    final deviceId = newId();
    try {
      await secrets.write(
        _databaseKey,
        base64UrlEncode(databaseKey.extractBytes()),
      );
      await secrets.write(_boxPublic, base64UrlEncode(encryption.publicKey));
      await secrets.write(
        _boxSecret,
        base64UrlEncode(encryption.secretKey.extractBytes()),
      );
      await secrets.write(_signPublic, base64UrlEncode(signing.publicKey));
      await secrets.write(
        _signSecret,
        base64UrlEncode(signing.secretKey.extractBytes()),
      );
      await secrets.write(_deviceId, deviceId);
      return DeviceKeyMaterial(
        databaseKey: databaseKey,
        encryptionPublicKey: encryption.publicKey,
        encryptionSecretKey: encryption.secretKey,
        signingPublicKey: signing.publicKey,
        signingSecretKey: signing.secretKey,
        deviceId: deviceId,
      );
    } catch (_) {
      databaseKey.dispose();
      encryption.dispose();
      signing.dispose();
      await secrets.deleteAll();
      rethrow;
    }
  }

  Future<void> destroy() => secrets.deleteAll();
}
