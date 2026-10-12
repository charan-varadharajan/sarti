import 'dart:async';

import 'package:sarti_mobile/src/core/network/sarti_api.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/features/push/push_sync_coordinator.dart';
import 'package:sarti_mobile/src/features/sync/sync_engine.dart';

typedef FamilyReader = FamilyCalendar? Function();
typedef FamilyProvisioner = Future<RemoteFamily> Function(
  String familyId,
  String calendarResourceId,
);
typedef FamilySynchronizer = Future<SyncReport> Function(String familyId);
typedef WakeUpSender = Future<int> Function(String familyId);
typedef PushInitializer = Future<FirebasePushInitialization> Function();

class AuthenticatedSyncRuntime {
  factory AuthenticatedSyncRuntime({
    required FamilyReader readFamily,
    required FamilyProvisioner provisionFamily,
    required FamilySynchronizer synchronizeFamily,
    required WakeUpSender sendWakeUp,
    required TokenRegistrar registerPushToken,
    required PushInitializer initializePush,
    void Function()? onRemoteApplied,
    void Function()? onSessionExpired,
    PushFailureReporter? reportPushFailure,
    Future<void> Function()? refreshSuggestions,
  }) => AuthenticatedSyncRuntime._(
    readFamily,
    provisionFamily,
    synchronizeFamily,
    sendWakeUp,
    registerPushToken,
    initializePush,
    onRemoteApplied,
    onSessionExpired,
    reportPushFailure,
    refreshSuggestions,
  );

  AuthenticatedSyncRuntime._(
    this._readFamily,
    this._provisionFamily,
    this._synchronizeFamily,
    this._sendWakeUp,
    this._registerPushToken,
    this._initializePush,
    this._onRemoteApplied,
    this._onSessionExpired,
    this._reportPushFailure,
    this._refreshSuggestions,
  );

  final FamilyReader _readFamily;
  final FamilyProvisioner _provisionFamily;
  final FamilySynchronizer _synchronizeFamily;
  final WakeUpSender _sendWakeUp;
  final TokenRegistrar _registerPushToken;
  final PushInitializer _initializePush;
  final void Function()? _onRemoteApplied;
  final void Function()? _onSessionExpired;
  final PushFailureReporter? _reportPushFailure;
  final Future<void> Function()? _refreshSuggestions;

  PushSyncCoordinator? _push;
  Future<void>? _activeSync;
  bool _pending = false;
  bool _disposed = false;
  final Set<String> _provisionedFamilies = {};

  Future<void> start() async {
    if (_disposed) return;
    final initialization = await _initializePush();
    final transport = initialization.transport;
    if (transport != null && !_disposed) {
      final coordinator = PushSyncCoordinator(
        transport: transport,
        registerToken: _registerPushToken,
        synchronize: synchronize,
        reportFailure: _reportPushFailure,
      );
      _push = coordinator;
      await coordinator.start();
    }
    await synchronize();
  }

  Future<void> synchronize() {
    if (_disposed) return Future<void>.value();
    final active = _activeSync;
    if (active != null) {
      _pending = true;
      return active;
    }
    final operation = _drain();
    _activeSync = operation;
    return operation;
  }

  Future<void> _drain() async {
    try {
      do {
        _pending = false;
        await _synchronizeOnce();
      } while (_pending && !_disposed);
    } finally {
      _activeSync = null;
    }
  }

  Future<void> _synchronizeOnce() async {
    final family = _readFamily();
    if (family == null) return;
    try {
      if (_provisionedFamilies.add(family.householdId)) {
        try {
          await _provisionFamily(family.householdId, family.calendarResourceId);
        } catch (_) {
          _provisionedFamilies.remove(family.householdId);
          rethrow;
        }
      }
      final report = await _synchronizeFamily(family.householdId);
      if (report.applied > 0 || report.conflicts > 0) _onRemoteApplied?.call();
      if (report.uploaded > 0) await _sendWakeUp(family.householdId);
      try {
        await _refreshSuggestions?.call();
      } catch (_) {
        // The inbox exposes its unavailable state. Email polling must not turn a
        // successful calendar upload into a retry or suppress its peer wake-up.
      }
    } on SartiApiException catch (error) {
      if (error.statusCode == 401) _onSessionExpired?.call();
      rethrow;
    }
  }

  void applicationForegrounded() {
    if (_push case final push?) {
      push.applicationForegrounded();
    } else {
      unawaited(synchronize());
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _push?.dispose();
  }
}
