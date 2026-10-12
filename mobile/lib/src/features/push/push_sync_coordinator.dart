import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

typedef TokenRegistrar = Future<void> Function(String token);
typedef SyncRequester = Future<void> Function();
typedef PushFailureReporter = void Function(PushFailure failure);

enum PushFailure { initialization, tokenRegistration, synchronization }

enum FirebasePushAvailability { available, unavailable }

class FirebasePushInitialization {
  const FirebasePushInitialization._(this.availability, this.transport);

  const FirebasePushInitialization.available(PushTransport transport)
    : this._(FirebasePushAvailability.available, transport);

  const FirebasePushInitialization.unavailable()
    : this._(FirebasePushAvailability.unavailable, null);

  final FirebasePushAvailability availability;
  final PushTransport? transport;
}

abstract interface class PushTransport {
  Future<String?> token();
  Stream<String> get tokenRefreshes;
  Stream<Map<String, String>> get foregroundMessages;
  Stream<Map<String, String>> get openedMessages;
}

class FirebasePushTransport implements PushTransport {
  FirebasePushTransport._(this._messaging);

  final FirebaseMessaging _messaging;

  static Future<FirebasePushInitialization> initialize() async {
    try {
      await Firebase.initializeApp();
      return FirebasePushInitialization.available(
        FirebasePushTransport._(FirebaseMessaging.instance),
      );
    } on FirebaseException {
      // Missing platform Firebase configuration is expected in local builds.
      // Return only a bounded state; never expose provider error text or tokens.
      return const FirebasePushInitialization.unavailable();
    }
  }

  @override
  Future<String?> token() => _messaging.getToken();

  @override
  Stream<String> get tokenRefreshes => _messaging.onTokenRefresh;

  @override
  Stream<Map<String, String>> get foregroundMessages =>
      FirebaseMessaging.onMessage.map(_data);

  @override
  Stream<Map<String, String>> get openedMessages =>
      FirebaseMessaging.onMessageOpenedApp.map(_data);

  static Map<String, String> _data(RemoteMessage message) =>
      Map<String, String>.unmodifiable(message.data);
}

/// Registers the current push token and turns an exact opaque wake-up into a
/// coalesced encrypted-sync request. It never accepts content-bearing payloads.
///
/// Construct this only after an authenticated API session and [SyncRequester]
/// are available. Background pushes are caught up by calling
/// [applicationForegrounded] when the authorized app returns to the foreground.
class PushSyncCoordinator {
  factory PushSyncCoordinator({
    required PushTransport transport,
    required TokenRegistrar registerToken,
    required SyncRequester synchronize,
    PushFailureReporter? reportFailure,
    Duration debounce = const Duration(milliseconds: 250),
  }) => PushSyncCoordinator._(
    transport,
    registerToken,
    synchronize,
    reportFailure,
    debounce,
  );

  PushSyncCoordinator._(
    this._transport,
    this._registerToken,
    this._synchronize,
    this._reportFailure,
    this._debounce,
  );

  final PushTransport _transport;
  final TokenRegistrar _registerToken;
  final SyncRequester _synchronize;
  final PushFailureReporter? _reportFailure;
  final Duration _debounce;
  final List<StreamSubscription<Object?>> _subscriptions = [];

  Timer? _timer;
  bool _started = false;
  bool _disposed = false;
  bool _syncing = false;
  bool _pending = false;

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    _subscriptions
      ..add(_transport.tokenRefreshes.listen(_registerSafely))
      ..add(_transport.foregroundMessages.listen(receive))
      ..add(_transport.openedMessages.listen(receive));
    try {
      final token = await _transport.token();
      if (token != null && token.isNotEmpty) await _registerToken(token);
    } catch (_) {
      _reportFailure?.call(PushFailure.tokenRegistration);
    }
  }

  void receive(Map<String, String> payload) {
    if (_disposed || !_isOpaqueWakeUp(payload)) return;
    _scheduleSync();
  }

  /// A foreground transition always catches up encrypted state. This also
  /// covers silent pushes that an OS coalesced, delayed, or delivered while the
  /// Dart isolate was suspended.
  void applicationForegrounded() {
    if (_started && !_disposed) _scheduleSync();
  }

  void _registerSafely(String token) {
    if (_disposed || token.isEmpty) return;
    unawaited(
      _registerToken(token).catchError((Object _) {
        _reportFailure?.call(PushFailure.tokenRegistration);
      }),
    );
  }

  void _scheduleSync() {
    _timer?.cancel();
    _timer = Timer(_debounce, () => unawaited(_drain()));
  }

  Future<void> _drain() async {
    if (_disposed) return;
    if (_syncing) {
      _pending = true;
      return;
    }
    _syncing = true;
    try {
      await _synchronize();
    } catch (_) {
      _reportFailure?.call(PushFailure.synchronization);
    } finally {
      _syncing = false;
      if (_pending && !_disposed) {
        _pending = false;
        _scheduleSync();
      }
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
  }

  static bool _isOpaqueWakeUp(Map<String, String> payload) =>
      payload.length == 1 && payload['type'] == 'sync_available';
}
