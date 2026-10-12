import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sarti_mobile/src/core/auth/native_passkey_adapter.dart';
import 'package:sarti_mobile/src/core/crypto/device_key_store.dart';
import 'package:sarti_mobile/src/features/sync/sync_engine.dart';

class AuthenticatedSession {
  const AuthenticatedSession({
    required this.adultId,
    required this.deviceId,
    required this.token,
    required this.expiresAt,
  });

  final String adultId;
  final String deviceId;
  final String token;
  final DateTime expiresAt;
}

class SartiApiException implements Exception {
  const SartiApiException(this.statusCode);
  final int statusCode;
}

class RemoteResource {
  const RemoteResource({
    required this.id,
    required this.kind,
    required this.keyEpoch,
  });

  final String id;
  final String kind;
  final int keyEpoch;
}

class RemoteFamily {
  const RemoteFamily({
    required this.id,
    required this.role,
    required this.status,
    required this.resources,
  });

  final String id;
  final String role;
  final String status;
  final List<RemoteResource> resources;
}

class EncryptedEmailDelivery {
  const EncryptedEmailDelivery({
    required this.suggestionId,
    required this.ciphertext,
    required this.receivedAt,
    required this.expiresAt,
  });

  final String suggestionId;
  final Uint8List ciphertext;
  final DateTime receivedAt;
  final DateTime expiresAt;
}

class SartiApiClient implements EncryptedRelay {
  SartiApiClient(this.baseUri, {HttpClient? httpClient, this.sessionToken})
    : _http = httpClient ?? HttpClient();

  final Uri baseUri;
  final HttpClient _http;
  String? sessionToken;

  Future<AuthenticatedSession> registerPasskey(
    NativePasskeyAdapter passkeys,
    DeviceKeyMaterial keys,
  ) async {
    final options = await _json('POST', '/v1/auth/registration/options');
    final credential = await passkeys.register(
      Map<String, dynamic>.from(options['public_key'] as Map),
    );
    final session = await _json(
      'POST',
      '/v1/auth/registration/complete',
      body: {
        'challenge_id': options['challenge_id'],
        'credential': credential,
        'device_keys': {
          'encryption_public_key': _encode(keys.encryptionPublicKey),
          'signing_public_key': _encode(keys.signingPublicKey),
        },
      },
    );
    sessionToken = session['session_token'] as String;
    return AuthenticatedSession(
      adultId: session['adult_id'] as String,
      deviceId: session['device_id'] as String,
      token: sessionToken!,
      expiresAt: DateTime.parse(session['expires_at'] as String),
    );
  }

  Future<AuthenticatedSession> authenticatePasskey(
    NativePasskeyAdapter passkeys,
    DeviceKeyMaterial keys,
  ) async {
    final options = await _json('POST', '/v1/auth/authentication/options');
    final credential = await passkeys.authenticate(
      Map<String, dynamic>.from(options['public_key'] as Map),
    );
    final session = await _json(
      'POST',
      '/v1/auth/authentication/complete',
      body: {
        'challenge_id': options['challenge_id'],
        'credential': credential,
        'device_keys': {
          'encryption_public_key': _encode(keys.encryptionPublicKey),
          'signing_public_key': _encode(keys.signingPublicKey),
        },
      },
    );
    sessionToken = session['session_token'] as String;
    return AuthenticatedSession(
      adultId: session['adult_id'] as String,
      deviceId: session['device_id'] as String,
      token: sessionToken!,
      expiresAt: DateTime.parse(session['expires_at'] as String),
    );
  }

  Future<void> registerPushToken(String token) async {
    await _json(
      'POST',
      '/v1/push/register',
      authenticated: true,
      body: {'fcm_token': token},
    );
  }

  Future<RemoteFamily> provisionFamily({
    required String familyId,
    required String calendarResourceId,
  }) async => _familyFromJson(
    await _json(
      'POST',
      '/v1/families',
      authenticated: true,
      body: {'family_id': familyId, 'calendar_resource_id': calendarResourceId},
    ),
  );

  Future<List<RemoteFamily>> listFamilies() async {
    final response = await _jsonList(
      'GET',
      '/v1/families',
      authenticated: true,
    );
    return response.map(_familyFromJson).toList(growable: false);
  }

  Future<RemoteBackup?> downloadBackup(String familyId) async {
    try {
      final response = await _backupRequest('GET', familyId);
      final bytes = await response.fold<List<int>>([], (all, chunk) {
        if (all.length + chunk.length > 10 * 1024 * 1024) {
          throw StateError('Backup exceeds size limit.');
        }
        return all..addAll(chunk);
      });
      return RemoteBackup(
        Uint8List.fromList(bytes),
        int.parse(response.headers.value('X-Backup-Revision')!),
        DateTime.parse(response.headers.value('X-Backup-Updated-At')!),
      );
    } on SartiApiException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<void> uploadBackup(
    String familyId,
    Uint8List bytes,
    int revision,
  ) async {
    final response = await _backupRequest(
      'PUT',
      familyId,
      bytes: bytes,
      revision: revision,
    );
    await response.drain<void>();
  }

  Future<void> deleteBackup(String familyId) async {
    final response = await _backupRequest('DELETE', familyId);
    await response.drain<void>();
  }

  Future<HttpClientResponse> _backupRequest(
    String method,
    String familyId, {
    Uint8List? bytes,
    int? revision,
  }) async {
    final token = sessionToken;
    if (token == null) throw StateError('Authentication required.');
    if (bytes != null && bytes.length > 10 * 1024 * 1024) {
      throw StateError('Backup exceeds size limit.');
    }
    final request = await _http.openUrl(
      method,
      baseUri.resolve('/v1/families/$familyId/backup'),
    );
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.headers.contentType = ContentType.binary;
    if (revision != null) request.headers.set('X-Backup-Revision', '$revision');
    if (bytes != null) request.add(bytes);
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      throw SartiApiException(response.statusCode);
    }
    return response;
  }

  Future<int> sendSyncWakeUp(String familyId) async {
    final response = await _json(
      'POST',
      '/v1/push/wake-up',
      authenticated: true,
      body: {'family_id': familyId},
    );
    return response['dispatched'] as int;
  }

  Future<List<EncryptedEmailDelivery>> listEmailSuggestions() async {
    final response = await _jsonList(
      'GET',
      '/v1/email/suggestions',
      authenticated: true,
    );
    return response
        .map(
          (value) => EncryptedEmailDelivery(
            suggestionId: value['suggestion_id'] as String,
            ciphertext: _decode(value['ciphertext'] as String),
            receivedAt: DateTime.parse(value['received_at'] as String),
            expiresAt: DateTime.parse(value['expires_at'] as String),
          ),
        )
        .toList(growable: false);
  }

  Future<void> dismissEmailSuggestion(String suggestionId) async {
    await _json(
      'DELETE',
      '/v1/email/suggestions/$suggestionId',
      authenticated: true,
    );
  }

  @override
  Future<void> upload(RelayEnvelope envelope) async {
    await _json(
      'POST',
      '/v1/sync/operations',
      authenticated: true,
      body: {
        'operation_id': envelope.operationId,
        'family_id': envelope.familyId,
        'resource_id': envelope.resourceId,
        'device_sequence': envelope.deviceSequence,
        'key_epoch': envelope.keyEpoch,
        'logical_version': envelope.logicalVersion,
        'nonce': _encode(envelope.nonce),
        'ciphertext': _encode(envelope.ciphertext),
        'content_digest': _encode(envelope.contentDigest),
      },
    );
  }

  @override
  Future<RelayPage> download(String familyId, int cursor) async {
    final response = await _json(
      'GET',
      '/v1/families/$familyId/sync?cursor=$cursor',
      authenticated: true,
    );
    final operations = (response['operations'] as List<Object?>).map((value) {
      final item = Map<String, dynamic>.from(value! as Map);
      return RelayEnvelope(
        serverSequence: item['server_sequence'] as int,
        operationId: item['operation_id'] as String,
        familyId: item['family_id'] as String,
        resourceId: item['resource_id'] as String,
        authorDeviceId: item['author_device_id'] as String,
        deviceSequence: item['device_sequence'] as int,
        keyEpoch: item['key_epoch'] as int,
        logicalVersion: Map<String, int>.from(item['logical_version'] as Map),
        nonce: _decode(item['nonce'] as String),
        ciphertext: _decode(item['ciphertext'] as String),
        contentDigest: _decode(item['content_digest'] as String),
      );
    }).toList();
    return RelayPage(operations, response['next_cursor'] as int);
  }

  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    Map<String, Object?>? body,
    bool authenticated = false,
  }) async {
    final request = await _http.openUrl(method, baseUri.resolve(path));
    request.headers.contentType = ContentType.json;
    if (authenticated) {
      final token = sessionToken;
      if (token == null) {
        throw StateError('An authenticated session is required.');
      }
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    if (body != null) {
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final bytes = await response.fold<List<int>>(
      <int>[],
      (all, value) => all..addAll(value),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SartiApiException(response.statusCode);
    }
    if (bytes.isEmpty) return <String, dynamic>{};
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
  }

  Future<List<Map<String, dynamic>>> _jsonList(
    String method,
    String path, {
    bool authenticated = false,
  }) async {
    final request = await _http.openUrl(method, baseUri.resolve(path));
    request.headers.contentType = ContentType.json;
    if (authenticated) {
      final token = sessionToken;
      if (token == null) {
        throw StateError('An authenticated session is required.');
      }
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    final response = await request.close();
    final bytes = await response.fold<List<int>>(
      <int>[],
      (all, value) => all..addAll(value),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SartiApiException(response.statusCode);
    }
    return (jsonDecode(utf8.decode(bytes)) as List<Object?>)
        .map((value) => Map<String, dynamic>.from(value! as Map))
        .toList(growable: false);
  }

  RemoteFamily _familyFromJson(Map<String, dynamic> value) => RemoteFamily(
    id: value['id'] as String,
    role: value['role'] as String,
    status: value['status'] as String,
    resources: (value['resources'] as List<Object?>)
        .map((item) {
          final resource = Map<String, dynamic>.from(item! as Map);
          return RemoteResource(
            id: resource['id'] as String,
            kind: resource['kind'] as String,
            keyEpoch: resource['key_epoch'] as int,
          );
        })
        .toList(growable: false),
  );

  String _encode(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  Uint8List _decode(String value) =>
      base64Url.decode(base64Url.normalize(value));

  void close() => _http.close(force: true);
}

class RemoteBackup {
  const RemoteBackup(this.bytes, this.revision, this.updatedAt);
  final Uint8List bytes;
  final int revision;
  final DateTime updatedAt;
}
