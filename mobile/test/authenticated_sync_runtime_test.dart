import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/core/network/sarti_api.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/features/push/push_sync_coordinator.dart';
import 'package:sarti_mobile/src/features/sync/authenticated_sync_runtime.dart';
import 'package:sarti_mobile/src/features/sync/sync_engine.dart';

void main() {
  const family = FamilyCalendar(
    householdId: 'family',
    name: 'Family',
    calendarResourceId: 'calendar',
    children: [],
    guardians: [],
    events: [],
    openConflicts: 0,
  );

  test('provisions once, syncs, and wakes peers after an upload', () async {
    var provisions = 0;
    var syncs = 0;
    var wakeUps = 0;
    final runtime = AuthenticatedSyncRuntime(
      readFamily: () => family,
      provisionFamily: (familyId, calendarId) async {
        provisions++;
        expect((familyId, calendarId), ('family', 'calendar'));
        return const RemoteFamily(
          id: 'family',
          role: 'owner',
          status: 'active',
          resources: [],
        );
      },
      synchronizeFamily: (_) async {
        syncs++;
        return const SyncReport(uploaded: 1, applied: 0, conflicts: 0);
      },
      sendWakeUp: (_) async {
        wakeUps++;
        return 1;
      },
      registerPushToken: (_) async {},
      initializePush: () async =>
          const FirebasePushInitialization.unavailable(),
    );

    await runtime.start();
    await runtime.synchronize();

    expect(provisions, 1);
    expect(syncs, 2);
    expect(wakeUps, 2);
    await runtime.dispose();
  });

  test('coalesces concurrent requests and reports remote changes', () async {
    final first = Completer<void>();
    var syncs = 0;
    var refreshes = 0;
    final runtime = AuthenticatedSyncRuntime(
      readFamily: () => family,
      provisionFamily: (_, _) async => const RemoteFamily(
        id: 'family',
        role: 'owner',
        status: 'active',
        resources: [],
      ),
      synchronizeFamily: (_) async {
        syncs++;
        if (syncs == 1) await first.future;
        return SyncReport(
          uploaded: 0,
          applied: syncs == 2 ? 1 : 0,
          conflicts: 0,
        );
      },
      sendWakeUp: (_) async => 0,
      registerPushToken: (_) async {},
      initializePush: () async =>
          const FirebasePushInitialization.unavailable(),
      onRemoteApplied: () => refreshes++,
    );

    final started = runtime.start();
    await Future<void>.delayed(Duration.zero);
    final second = runtime.synchronize();
    final third = runtime.synchronize();
    first.complete();
    await Future.wait([started, second, third]);

    expect(syncs, 2);
    expect(refreshes, 1);
    await runtime.dispose();
  });

  test('expires the local session after an authenticated 401', () async {
    var expired = 0;
    final runtime = AuthenticatedSyncRuntime(
      readFamily: () => family,
      provisionFamily: (_, _) async => throw const SartiApiException(401),
      synchronizeFamily: (_) async =>
          const SyncReport(uploaded: 0, applied: 0, conflicts: 0),
      sendWakeUp: (_) async => 0,
      registerPushToken: (_) async {},
      initializePush: () async =>
          const FirebasePushInitialization.unavailable(),
      onSessionExpired: () => expired++,
    );

    await expectLater(runtime.start(), throwsA(isA<SartiApiException>()));
    expect(expired, 1);
    await runtime.dispose();
  });

  test('email refresh failure does not suppress an uploaded wake-up', () async {
    var wakeUps = 0;
    final runtime = AuthenticatedSyncRuntime(
      readFamily: () => family,
      provisionFamily: (_, _) async => const RemoteFamily(
        id: 'family',
        role: 'owner',
        status: 'active',
        resources: [],
      ),
      synchronizeFamily: (_) async =>
          const SyncReport(uploaded: 1, applied: 0, conflicts: 0),
      sendWakeUp: (_) async {
        wakeUps++;
        return 1;
      },
      registerPushToken: (_) async {},
      initializePush: () async =>
          const FirebasePushInitialization.unavailable(),
      refreshSuggestions: () async => throw StateError('unavailable'),
    );

    await runtime.start();

    expect(wakeUps, 1);
    await runtime.dispose();
  });
}
