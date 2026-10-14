import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/core/network/sarti_api.dart';

void main() {
  test('ADULT-API-001 personal provisioning is metadata-only and backups use adult-scoped routes', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final paths = <String>[];
    final bodies = <Uint8List>[];
    final subscription = server.listen((request) async {
      expect(request.headers.value('authorization'), 'Bearer fixture-session');
      paths.add(request.uri.path);
      bodies.add(
        Uint8List.fromList(
          await request.fold<List<int>>([], (all, chunk) => all..addAll(chunk)),
        ),
      );
      if (request.uri.path.endsWith('/resources')) {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'id': 'personal-resource',
            'kind': 'personal_calendar',
            'key_epoch': 1,
          }),
        );
      } else if (request.method == 'GET') {
        request.response.headers.set('X-Backup-Revision', '1');
        request.response.headers.set(
          'X-Backup-Updated-At',
          '2026-10-13T00:00:00Z',
        );
        request.response.add([83, 65, 82, 84, 2, ...List<int>.filled(100, 17)]);
      } else {
        request.response.statusCode = 204;
      }
      await request.response.close();
    });
    final api = SartiApiClient(
      Uri.parse('http://127.0.0.1:${server.port}'),
      sessionToken: 'fixture-session',
    );
    try {
      final resource = await api.provisionResource(
        'family',
        'personal-resource',
        'personal_calendar',
      );
      expect(resource.kind, 'personal_calendar');
      expect(jsonDecode(utf8.decode(bodies.first)), {
        'resource_id': 'personal-resource',
        'kind': 'personal_calendar',
        'share_with_calendar_guardians': false,
      });
      final blob = Uint8List.fromList([
        83,
        65,
        82,
        84,
        2,
        ...List<int>.filled(100, 17),
      ]);
      await api.uploadBackup('family', blob, 0, personal: true);
      expect((await api.downloadBackup('family', personal: true))!.bytes, blob);
      await api.deleteBackup('family', personal: true);
      expect(
        paths.skip(1).every((p) => p == '/v1/families/family/personal-backup'),
        isTrue,
      );
      expect(bodies[1], blob);
    } finally {
      api.close();
      await subscription.cancel();
      await server.close(force: true);
    }
  });
}
