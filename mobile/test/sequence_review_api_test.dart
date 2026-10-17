import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/core/network/sarti_api.dart';
import 'package:sarti_mobile/src/features/sync/sync_engine.dart';

void main() {
  for (final changeSession in [false, true]) {
    test(
      'S5-OFFLINE-API-${changeSession ? '002' : '001'} receipt request has metadata only and pins the session',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        late SartiApiClient api;
        final listener = server.listen((request) async {
          expect(request.method, 'POST');
          expect(request.uri.toString(), '/v1/sync/sequence-review');
          expect(
            request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer fixture-session',
          );
          final body =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          expect(body.keys.toSet(), {
            'operation_id',
            'family_id',
            'resource_id',
            'device_sequence',
            'content_digest',
          });
          expect(body['operation_id'], 'original-operation');
          expect(body['device_sequence'], 7);
          if (changeSession) api.sessionToken = 'changed-fixture-session';
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'operation_id': 'original-operation',
              'device_id': 'device',
              'last_device_sequence': 7,
              'receipt': 'unknown',
            }),
          );
          await request.response.close();
        });
        api = SartiApiClient(
          Uri.parse('http://127.0.0.1:${server.port}'),
          sessionToken: 'fixture-session',
        );
        addTearDown(() async {
          api.close();
          await listener.cancel();
          await server.close(force: true);
        });
        final operation = api.reviewSequence(
          RelayEnvelope(
            serverSequence: 0,
            operationId: 'original-operation',
            familyId: 'family',
            resourceId: 'resource',
            authorDeviceId: 'device',
            deviceSequence: 7,
            keyEpoch: 1,
            logicalVersion: const {'device': 1},
            nonce: Uint8List(24),
            ciphertext: Uint8List(48),
            contentDigest: Uint8List(32),
          ),
        );
        if (changeSession) {
          await expectLater(operation, throwsStateError);
        } else {
          final result = await operation;
          expect(result.receipt, 'unknown');
          expect(result.lastDeviceSequence, 7);
        }
      },
    );
  }
}
