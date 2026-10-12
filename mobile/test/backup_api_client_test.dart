import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/core/network/sarti_api.dart';

void main() {
  test(
    'BUG-002 authenticated transport uploads and downloads only opaque bytes',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      Uint8List? uploaded;
      final blob = Uint8List.fromList([
        83,
        65,
        82,
        84,
        2,
        ...List.filled(100, 137),
      ]);
      final subscription = server.listen((request) async {
        expect(request.uri.path, '/v1/families/family-a/backup');
        expect(
          request.headers.value('authorization'),
          'Bearer synthetic-session',
        );
        if (request.method == 'PUT') {
          expect(request.headers.value('X-Backup-Revision'), '0');
          uploaded = Uint8List.fromList(
            await request.fold<List<int>>(
              [],
              (all, chunk) => all..addAll(chunk),
            ),
          );
          request.response.statusCode = 204;
        } else if (request.method == 'GET') {
          request.response.headers.set('X-Backup-Revision', '1');
          request.response.headers.set(
            'X-Backup-Updated-At',
            '2026-10-12T00:00:00Z',
          );
          request.response.add(blob);
        } else {
          request.response.statusCode = 204;
        }
        await request.response.close();
      });
      final api = SartiApiClient(
        Uri.parse('http://127.0.0.1:${server.port}'),
        sessionToken: 'synthetic-session',
      );
      try {
        await api.uploadBackup('family-a', blob, 0);
        expect(uploaded, blob);
        final downloaded = await api.downloadBackup('family-a');
        expect(downloaded!.bytes, blob);
        expect(downloaded.revision, 1);
        await api.deleteBackup('family-a');
      } finally {
        api.close();
        await subscription.cancel();
        await server.close(force: true);
      }
    },
  );
}
