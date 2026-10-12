import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/core/network/sarti_api.dart';

void main() {
  test(
    'CHILD-API-001 authenticated transport sends metadata and sealed keys only',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <Map<String, dynamic>>[];
      final subscription = server.listen((request) async {
        expect(
          request.headers.value('authorization'),
          'Bearer fixture-session',
        );
        final text = await utf8.decoder.bind(request).join();
        if (text.isNotEmpty) {
          requests.add(jsonDecode(text) as Map<String, dynamic>);
        }
        final path = request.uri.path;
        Object result;
        if (path.endsWith('/devices')) {
          result = [
            {
              'device_id': 'recipient',
              'encryption_public_key': base64UrlEncode(Uint8List(32)),
              'signing_public_key': base64UrlEncode(Uint8List(32)),
              'permission': 'read',
              'has_current_grant': false,
            },
          ];
        } else if (path.endsWith('/resources')) {
          result = {
            'id': 'child-resource',
            'kind': 'child_profile',
            'key_epoch': 1,
          };
        } else if (request.method == 'GET') {
          result = [
            {
              'resource_id': 'child-resource',
              'key_epoch': 1,
              'recipient_device_id': 'recipient',
              'granter_device_id': 'granter',
              'wrapped_key': base64UrlEncode(Uint8List(80)),
              'signature': base64UrlEncode(Uint8List(64)),
            },
          ];
        } else {
          result = <String, Object>{};
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(result));
        await request.response.close();
      });
      final api = SartiApiClient(
        Uri.parse('http://127.0.0.1:${server.port}'),
        sessionToken: 'fixture-session',
      );
      try {
        final resource = await api.provisionChild(
          'family',
          'child-resource',
          shareWithCalendarGuardians: true,
        );
        expect(resource.kind, 'child_profile');
        expect(
          (await api.resourceDevices('family', resource.id)).single.permission,
          'read',
        );
        final grant = (await api.keyGrants()).single;
        expect(grant.wrappedKey, hasLength(80));
        await api.uploadKeyGrant('family', grant);
        expect(requests.first, {
          'resource_id': 'child-resource',
          'kind': 'child_profile',
          'share_with_calendar_guardians': true,
        });
        expect(requests.last.keys.toSet(), {
          'family_id',
          'resource_id',
          'key_epoch',
          'recipient_device_id',
          'wrapped_key',
          'signature',
        });
      } finally {
        api.close();
        await subscription.cancel();
        await server.close(force: true);
      }
    },
  );
}
