import 'dart:convert';

import 'package:sarti_mobile/src/core/crypto/device_key_store.dart';
import 'package:sarti_mobile/src/core/network/sarti_api.dart';

class SessionStore {
  SessionStore(this._secrets);

  final SecretStore _secrets;
  static const _sessionKey = 'authenticated-session-v1';
  static const _lastDeviceKey = 'authenticated-device-id-v1';

  Future<AuthenticatedSession?> load({DateTime? now}) async {
    final value = await _secrets.read(_sessionKey);
    if (value == null) return null;
    try {
      final json = Map<String, Object?>.from(jsonDecode(value) as Map);
      final session = AuthenticatedSession(
        adultId: json['adult_id']! as String,
        deviceId: json['device_id']! as String,
        token: json['token']! as String,
        expiresAt: DateTime.parse(json['expires_at']! as String),
      );
      if (!session.expiresAt.isAfter(now ?? DateTime.now().toUtc())) {
        await clear();
        return null;
      }
      return session;
    } on FormatException {
      await clear();
      return null;
    } on TypeError {
      await clear();
      return null;
    }
  }

  Future<void> save(AuthenticatedSession session) async {
    await _secrets.write(_lastDeviceKey, session.deviceId);
    await _secrets.write(
      _sessionKey,
      jsonEncode({
        'adult_id': session.adultId,
        'device_id': session.deviceId,
        'token': session.token,
        'expires_at': session.expiresAt.toUtc().toIso8601String(),
      }),
    );
  }

  Future<String?> lastDeviceId() => _secrets.read(_lastDeviceKey);

  /// Removes the remote bearer session while retaining the non-secret device
  /// identifier needed to keep local vector clocks stable during offline use.
  Future<void> clear() => _secrets.delete(_sessionKey);
}
