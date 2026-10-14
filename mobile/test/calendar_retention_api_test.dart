import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/core/network/sarti_api.dart';

void main() {
  test(
    'RETENTION-API-CLIENT-001 bounded preference requests and stale revisions',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var revision = 0;
      final listener = server.listen((request) async {
        expect(
          request.uri.path,
          '/v1/families/prepared-family/calendar-retention',
        );
        expect(
          request.headers.value('authorization'),
          'Bearer synthetic-session',
        );
        if (request.method == 'PUT') {
          final body =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          expect(body.keys.toSet(), {'period', 'revision'});
          if (body['revision'] != revision) {
            request.response.statusCode = 409;
            await request.response.close();
            return;
          }
          expect(body['period'], 'never');
          revision++;
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'period': revision == 0 ? 'week' : 'never',
            'revision': revision,
            'enabled': true,
            'can_manage': true,
          }),
        );
        await request.response.close();
      });
      final api = SartiApiClient(
        Uri.parse('http://127.0.0.1:${server.port}'),
        sessionToken: 'synthetic-session',
      );
      try {
        expect(
          (await api.calendarRetention('prepared-family'))['period'],
          'week',
        );
        expect(
          (await api.setCalendarRetention(
            'prepared-family',
            'never',
            0,
          ))['revision'],
          1,
        );
        await expectLater(
          api.setCalendarRetention('prepared-family', 'never', 0),
          throwsA(
            isA<SartiApiException>().having((e) => e.statusCode, 'status', 409),
          ),
        );
      } finally {
        api.close();
        await listener.cancel();
        await server.close(force: true);
      }
    },
  );
}
