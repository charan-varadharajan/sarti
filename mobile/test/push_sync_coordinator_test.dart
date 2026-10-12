import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/features/push/push_sync_coordinator.dart';

void main() {
  test(
    'registers initial and refreshed tokens without logging content',
    () async {
      final transport = _FakePushTransport(initialToken: 'initial-token');
      final registered = <String>[];
      final coordinator = PushSyncCoordinator(
        transport: transport,
        registerToken: (token) async => registered.add(token),
        synchronize: () async {},
        debounce: Duration.zero,
      );

      await coordinator.start();
      transport.tokenRefreshController.add('refreshed-token');
      await _flush();

      expect(registered, ['initial-token', 'refreshed-token']);
      await coordinator.dispose();
      await transport.dispose();
    },
  );

  test('accepts only the exact opaque wake-up payload', () async {
    final transport = _FakePushTransport();
    var syncs = 0;
    final coordinator = PushSyncCoordinator(
      transport: transport,
      registerToken: (_) async {},
      synchronize: () async => syncs++,
      debounce: Duration.zero,
    );
    await coordinator.start();

    transport.messageController
      ..add({'type': 'other'})
      ..add({'type': 'sync_available', 'family_id': 'private'})
      ..add({'type': 'sync_available'});
    await _flush();

    expect(syncs, 1);
    await coordinator.dispose();
    await transport.dispose();
  });

  test('coalesces duplicate wake-ups into one sync', () async {
    final transport = _FakePushTransport();
    var syncs = 0;
    final coordinator = PushSyncCoordinator(
      transport: transport,
      registerToken: (_) async {},
      synchronize: () async => syncs++,
      debounce: const Duration(milliseconds: 10),
    );
    await coordinator.start();

    for (var index = 0; index < 20; index++) {
      transport.messageController.add({'type': 'sync_available'});
    }
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(syncs, 1);
    await coordinator.dispose();
    await transport.dispose();
  });

  test('coalesces wake-ups received during a running sync', () async {
    final transport = _FakePushTransport();
    final firstSync = Completer<void>();
    var syncs = 0;
    final coordinator = PushSyncCoordinator(
      transport: transport,
      registerToken: (_) async {},
      synchronize: () async {
        syncs++;
        if (syncs == 1) await firstSync.future;
      },
      debounce: Duration.zero,
    );
    await coordinator.start();

    transport.messageController.add({'type': 'sync_available'});
    await _flush();
    for (var index = 0; index < 10; index++) {
      transport.messageController.add({'type': 'sync_available'});
    }
    await _flush();
    firstSync.complete();
    await _flush();

    expect(syncs, 2);
    await coordinator.dispose();
    await transport.dispose();
  });

  test('foreground transition requests one catch-up sync', () async {
    final transport = _FakePushTransport();
    var syncs = 0;
    final coordinator = PushSyncCoordinator(
      transport: transport,
      registerToken: (_) async {},
      synchronize: () async => syncs++,
      debounce: Duration.zero,
    );
    await coordinator.start();

    coordinator.applicationForegrounded();
    await _flush();

    expect(syncs, 1);
    await coordinator.dispose();
    await transport.dispose();
  });

  test('reports bounded failures and exposes no provider exception', () async {
    final transport = _FakePushTransport(initialToken: 'token');
    final failures = <PushFailure>[];
    final coordinator = PushSyncCoordinator(
      transport: transport,
      registerToken: (_) => throw StateError('secret provider detail'),
      synchronize: () => throw StateError('private sync detail'),
      reportFailure: failures.add,
      debounce: Duration.zero,
    );

    await coordinator.start();
    transport.messageController.add({'type': 'sync_available'});
    await _flush();

    expect(failures, [
      PushFailure.tokenRegistration,
      PushFailure.synchronization,
    ]);
    await coordinator.dispose();
    await transport.dispose();
  });
}

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _FakePushTransport implements PushTransport {
  _FakePushTransport({this.initialToken});

  final String? initialToken;
  final tokenRefreshController = StreamController<String>.broadcast();
  final messageController = StreamController<Map<String, String>>.broadcast();
  final openedController = StreamController<Map<String, String>>.broadcast();

  @override
  Stream<Map<String, String>> get foregroundMessages =>
      messageController.stream;

  @override
  Stream<Map<String, String>> get openedMessages => openedController.stream;

  @override
  Future<String?> token() async => initialToken;

  @override
  Stream<String> get tokenRefreshes => tokenRefreshController.stream;

  Future<void> dispose() async {
    await tokenRefreshController.close();
    await messageController.close();
    await openedController.close();
  }
}
