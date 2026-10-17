import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/core/auth/native_passkey_adapter.dart';
import 'package:sarti_mobile/src/core/network/sarti_api.dart';

class FixturePasskey extends NativePasskeyAdapter {
  FixturePasskey(this.action);
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) action;
  @override
  Future<Map<String, dynamic>> authenticate(Map<String, dynamic> options) =>
      action(options);
}

void main() {
  for (final switchAccount in [false, true]) {
    test(
      'S5-AUTH-MOB-${switchAccount ? '002' : '001'} current-device confirmation and changed-session denial',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final paths = <String>[];
        final bodies = <Map>[];
        final listener = server.listen((request) async {
          paths.add(request.uri.toString());
          expect(
            request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer fixture-session',
          );
          bodies.add(
            jsonDecode(await utf8.decoder.bind(request).join()) as Map,
          );
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode(
              paths.length == 1
                  ? {
                      'challenge_id': 'fixture',
                      'public_key': {'challenge': 'fixture'},
                    }
                  : {'proof': 'fixture-proof'},
            ),
          );
          await request.response.close();
        });
        final api = SartiApiClient(
          Uri.parse('http://127.0.0.1:${server.port}'),
          sessionToken: 'fixture-session',
        );
        addTearDown(() async {
          api.close();
          await listener.cancel();
          await server.close(force: true);
        });
        final result = api.confirmSensitiveAction(
          FixturePasskey((options) async {
            expect(options['challenge'], 'fixture');
            if (switchAccount) api.sessionToken = 'other-fixture-session';
            return {'id': 'fixture-credential'};
          }),
          action: 'export',
          familyId: 'family-a',
          targetId: 'resource-a',
          aclRevision: 2,
        );
        if (switchAccount) {
          await expectLater(result, throwsA(isA<SartiApiException>()));
          expect(paths, ['/v1/auth/step-up/options']);
        } else {
          expect(await result, 'fixture-proof');
          expect(api.sessionToken, 'fixture-session');
          expect(paths, [
            '/v1/auth/step-up/options',
            '/v1/auth/step-up/complete',
          ]);
          expect(bodies.first.keys.toSet(), {
            'action',
            'family_id',
            'target_id',
            'acl_revision',
          });
          expect(bodies.last.keys.toSet(), {'challenge_id', 'credential'});
        }
        expect(bodies.any((body) => body.containsKey('device_keys')), isFalse);
      },
    );
  }
}
