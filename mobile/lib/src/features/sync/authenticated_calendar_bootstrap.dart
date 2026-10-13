import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:sarti_mobile/src/core/auth/native_passkey_adapter.dart';
import 'package:sarti_mobile/src/core/auth/session_store.dart';
import 'package:sarti_mobile/src/core/crypto/device_key_store.dart';
import 'package:sarti_mobile/src/core/crypto/resource_crypto.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/core/network/sarti_api.dart';
import 'package:sarti_mobile/src/features/ai/cloud_ai_consent.dart';
import 'package:sarti_mobile/src/features/ai/native_ai_provider.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/features/calendar/data/reminder_scheduler.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_controller.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_screen.dart';
import 'package:sarti_mobile/src/features/email/email_suggestion_inbox.dart';
import 'package:sarti_mobile/src/features/push/push_sync_coordinator.dart';
import 'package:sarti_mobile/src/features/sync/resource_key_sync.dart';
import 'package:sarti_mobile/src/features/sync/authenticated_sync_runtime.dart';
import 'package:sarti_mobile/src/features/sync/sync_engine.dart';
import 'package:sodium/sodium.dart';
import 'package:sarti_mobile/src/core/backup/backup_service.dart';
import 'package:sarti_mobile/src/features/backup/backup_recovery.dart';
import 'package:sarti_mobile/src/features/backup/backup_screen.dart';

import 'package:sarti_mobile/src/features/guardians/guardian_coordinator.dart';
import 'package:sarti_mobile/src/features/guardians/guardian_screen.dart';
import 'package:sarti_mobile/src/features/guardians/invitation_links.dart';

class AuthenticatedCalendarBootstrap extends StatefulWidget {
  const AuthenticatedCalendarBootstrap({
    super.key,
    required this.database,
    required this.keys,
    required this.sodium,
    required this.secrets,
    required this.reminders,
    required this.timezone,
    this.onRecovered,
    this.apiBaseUrl = const String.fromEnvironment('SARTI_API_BASE_URL'),
  });

  final SartiDatabase database;
  final DeviceKeyMaterial keys;
  final Sodium sodium;
  final SecretStore secrets;
  final ReminderScheduler reminders;
  final String timezone;
  final VoidCallback? onRecovered;
  final String apiBaseUrl;

  @override
  State<AuthenticatedCalendarBootstrap> createState() =>
      _AuthenticatedCalendarBootstrapState();
}

class _AuthenticatedCalendarBootstrapState
    extends State<AuthenticatedCalendarBootstrap>
    with WidgetsBindingObserver {
  SartiApiClient? _api;
  AuthenticatedSyncRuntime? _runtime;
  CalendarController? _controller;
  GuardianCoordinator? _guardians;
  bool _guardianRouteOpen = false;
  EmailSuggestionInbox? _emailInbox;
  late final SessionStore _sessions = SessionStore(widget.secrets);
  bool _loading = true;
  bool _authenticating = false;
  bool _needsAuthentication = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    InvitationLinks.token.addListener(_invitationReceived);
    unawaited(_initialize());
  }

  void _invitationReceived() {
    if (!mounted || InvitationLinks.token.value == null) return;
    if (_api?.sessionToken != null && _guardians != null) {
      unawaited(_openGuardians());
    } else {
      setState(() {});
    }
  }

  void _guardianChanged() {
    if (mounted) setState(() {});
  }

  bool get _canWriteCalendar {
    final local = _controller?.family;
    if (local == null) return false;
    final rows = widget.database.raw.select(
      'SELECT value FROM app_preferences WHERE key=?',
      ['family-access-${local.householdId}'],
    );
    if (rows.isEmpty) {
      return true; // Existing/offline owner before provisioning.
    }
    final access = jsonDecode(rows.single['value'] as String) as Map;
    return access['role'] == 'owner' ||
        {'write', 'admin'}.contains(access['permission']);
  }

  bool get _canManageFamily {
    final local = _controller?.family;
    if (local == null) return false;
    final rows = widget.database.raw.select(
      'SELECT value FROM app_preferences WHERE key=?',
      ['family-access-${local.householdId}'],
    );
    return rows.isEmpty ||
        (jsonDecode(rows.single['value'] as String) as Map)['role'] == 'owner';
  }

  Future<void> _openGuardians() async {
    final guardians = _guardians;
    if (guardians == null || _guardianRouteOpen || !mounted) return;
    _guardianRouteOpen = true;
    try {
      await guardians.refresh();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => GuardianScreen(
            coordinator: guardians,
            initialInvitation: InvitationLinks.token.value,
            onOpenCalendar: () => Navigator.of(context).pop(),
          ),
        ),
      );
    } finally {
      _guardianRouteOpen = false;
    }
  }

  Future<void> _initialize() async {
    final endpoint = widget.apiBaseUrl.trim();
    if (endpoint.isEmpty) {
      _activateOffline();
      return;
    }
    final uri = Uri.tryParse(endpoint);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      _showConfigurationError();
      return;
    }
    if (uri.scheme != 'https' && !_isLoopback(uri.host)) {
      _showConfigurationError();
      return;
    }
    _api = SartiApiClient(uri);
    final session = await _sessions.load();
    if (!mounted) return;
    if (session == null) {
      final lastDeviceId = await _sessions.lastDeviceId();
      if (!mounted) return;
      if (lastDeviceId != null) {
        _activateOffline(deviceId: lastDeviceId, needsAuthentication: true);
      } else {
        setState(() => _loading = false);
      }
      return;
    }
    await _activateAuthenticated(session);
  }

  bool _isLoopback(String host) =>
      host == 'localhost' || host == '127.0.0.1' || host == '::1';

  void _showConfigurationError() {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _message = 'The configured Sarti service address is invalid.';
    });
  }

  CalendarController _newController(String deviceId, {void Function()? sync}) {
    return CalendarController(
      CalendarRepository(widget.database, deviceId: deviceId),
      timezone: widget.timezone,
      reminders: widget.reminders,
      onFamilyCreated: (family) {
        final key = ResourceCrypto(widget.sodium).newResourceKey();
        try {
          widget.database.setResourceKey(
            family.calendarResourceId,
            1,
            key.extractBytes(),
          );
        } finally {
          key.dispose();
        }
      },
      onLocalMutation: sync,
    );
  }

  void _activateOffline({String? deviceId, bool needsAuthentication = false}) {
    if (!mounted) return;
    setState(() {
      _controller = _newController(deviceId ?? widget.keys.deviceId);
      _loading = false;
      _needsAuthentication = needsAuthentication;
      _message = needsAuthentication
          ? 'Your calendar remains available offline. Authenticate to resume secure sync.'
          : null;
    });
  }

  Future<void> _authenticate({required bool register}) async {
    final api = _api;
    if (api == null || _authenticating) return;
    setState(() {
      _authenticating = true;
      _message = null;
    });
    try {
      final passkeys = NativePasskeyAdapter();
      final session = register
          ? await api.registerPasskey(passkeys, widget.keys)
          : await api.authenticatePasskey(passkeys, widget.keys);
      await _sessions.save(session);
      await _activateAuthenticated(session);
    } catch (_) {
      if (mounted) {
        setState(() {
          _authenticating = false;
          _message = 'Authentication did not complete. Please try again.';
        });
      }
    }
  }

  Future<void> _activateAuthenticated(AuthenticatedSession session) async {
    final api = _api!;
    api.sessionToken = session.token;
    late final AuthenticatedSyncRuntime runtime;
    final controller = _newController(
      session.deviceId,
      sync: () => unawaited(
        runtime.synchronize().catchError((Object _) => _showSyncIssue()),
      ),
    );
    final engine = SyncEngine(
      database: widget.database,
      repository: controller.repository,
      crypto: ResourceCrypto(widget.sodium),
      sodium: widget.sodium,
      relay: api,
      deviceId: session.deviceId,
    );
    final emailInbox = EmailSuggestionInbox(
      sodium: widget.sodium,
      keys: widget.keys,
      fetch: api.listEmailSuggestions,
      dismissRemote: api.dismissEmailSuggestion,
    );
    final resourceKeys = ResourceKeySync(
      database: widget.database,
      repository: controller.repository,
      sodium: widget.sodium,
      keys: widget.keys,
      deviceId: session.deviceId,
      api: api,
    );
    runtime = AuthenticatedSyncRuntime(
      readFamily: () => controller.family,
      provisionFamily: (familyId, calendarId) async {
        final registered = await api.listFamilies();
        final existing = registered
            .where((f) => f.id == familyId && f.status == 'active')
            .firstOrNull;
        return existing ??
            await api.provisionFamily(
              familyId: familyId,
              calendarResourceId: calendarId,
            );
      },
      synchronizeFamily: (familyId) async {
        await resourceKeys.prepare(familyId);
        return engine.synchronize(familyId);
      },
      sendWakeUp: api.sendSyncWakeUp,
      registerPushToken: api.registerPushToken,
      initializePush: FirebasePushTransport.initialize,
      onRemoteApplied: controller.refresh,
      onSessionExpired: () => unawaited(_expireSession()),
      reportPushFailure: (_) => _showSyncIssue(),
      refreshSuggestions: emailInbox.refresh,
    );
    _guardians?.removeListener(_guardianChanged);
    _guardians?.dispose();
    _guardians = GuardianCoordinator(
      database: widget.database,
      repository: controller.repository,
      api: api,
      keys: widget.keys,
      synchronize: runtime.synchronize,
      onLocalChanged: controller.refresh,
    )..addListener(_guardianChanged);
    await _runtime?.dispose();
    _emailInbox?.dispose();
    _runtime = runtime;
    _emailInbox = emailInbox;
    if (!mounted) return;
    setState(() {
      _controller = controller;
      _loading = false;
      _authenticating = false;
      _needsAuthentication = false;
      _message = null;
    });
    unawaited(runtime.start().catchError((Object _) => _showSyncIssue()));
    unawaited(
      _guardians!.refresh().then((_) {
        if (!mounted) return;
        if (InvitationLinks.token.value != null ||
            _guardians?.family?.role == 'guardian' && !_guardians!.ready) {
          unawaited(_openGuardians());
        } else if (controller.family == null) {
          unawaited(_openBackup(discover: true));
        }
      }),
    );
  }

  Future<void> _openBackup({bool discover = false}) async {
    final api = _api;
    if (api == null || api.sessionToken == null) return;
    try {
      final families = (await api.listFamilies())
          .where((f) => f.role == 'owner' && f.status == 'active')
          .toList();
      final local = _controller?.family;
      if (local != null) families.removeWhere((f) => f.id != local.householdId);
      if (families.isEmpty || !mounted) return;
      // P0 has one local family; discover only backups this owner can access.
      for (final family in families) {
        var backup = await api.downloadBackup(family.id);
        if (discover && backup == null) continue;
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => BackupScreen(
              hasBackup: backup != null,
              canCreate: local != null,
              updatedAt: backup?.updatedAt,
              generatePhrase: () =>
                  BackupService.generateRecoveryPhrase(sodium: widget.sodium),
              create: (phrase) async {
                final key = widget.keys.databaseKey.extractBytes();
                try {
                  final bytes = await BackupRecovery.snapshot(
                    database: widget.database,
                    key: key,
                    phrase: phrase,
                    sodium: widget.sodium,
                    familyId: family.id,
                  );
                  await api.uploadBackup(
                    family.id,
                    bytes,
                    backup?.revision ?? 0,
                  );
                  backup = await api.downloadBackup(family.id);
                } finally {
                  key.fillRange(0, key.length, 0);
                }
              },
              remove: () async {
                await api.deleteBackup(family.id);
                backup = null;
              },
              restore: (phrase) async {
                await BackupRecovery.stage(
                  blob: backup!.bytes,
                  phrase: phrase,
                  familyId: family.id,
                  current: widget.database,
                  sodium: widget.sodium,
                  secrets: widget.secrets,
                );
                await _runtime?.dispose();
                _runtime = null;
                if (!mounted) return;
                Navigator.of(this.context).pop();
                widget.onRecovered?.call();
              },
            ),
          ),
        );
        return;
      }
    } catch (_) {
      _showSyncIssue();
    }
  }

  void _showSyncIssue() {
    if (!mounted) return;
    setState(() {
      _message = 'Sarti will retry secure synchronization when available.';
    });
  }

  Future<void> _expireSession() async {
    _guardians?.removeListener(_guardianChanged);
    _guardians?.dispose();
    _guardians = null;
    await _sessions.clear();
    await _runtime?.dispose();
    _runtime = null;
    _emailInbox?.dispose();
    _emailInbox = null;
    _api?.sessionToken = null;
    if (!mounted) return;
    setState(() {
      _needsAuthentication = true;
      _message = 'Your calendar remains available offline. Authenticate to resume secure sync.';
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_guardians?.refresh());
      _runtime?.applicationForegrounded();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    InvitationLinks.token.removeListener(_invitationReceived);
    _guardians?.removeListener(_guardianChanged);
    _guardians?.dispose();
    unawaited(_runtime?.dispose());
    _emailInbox?.dispose();
    _api?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final controller = _controller;
    if (controller != null) {
      return Stack(
        children: [
          CalendarScreen(
            controller: controller,
            canWrite: _canWriteCalendar,
            canManageChildren: _canManageFamily,
            onGuardians: _api?.sessionToken == null
                ? null
                : () => unawaited(_openGuardians()),
            nativeAi: NativeEventAiProvider(),
            cloudAiConsent: CloudAiConsentController(
              CloudAiConsentStore(widget.database),
            ),
            emailInbox: _emailInbox,
            onBackup: _api?.sessionToken == null || !_canManageFamily
                ? null
                : () => unawaited(_openBackup()),
          ),
          if (_api?.sessionToken != null &&
              (controller.family == null ||
                  _guardians?.family?.role == 'guardian' && !_guardians!.ready))
            Positioned(
              bottom: MediaQuery.paddingOf(context).bottom + 16,
              left: 16,
              right: 16,
              child: FilledButton.tonal(
                onPressed: () => unawaited(_openGuardians()),
                child: const Text('Join or review family invitation'),
              ),
            ),
          if (controller.family == null && _api?.sessionToken != null)
            Positioned(
              top: MediaQuery.paddingOf(context).top,
              right: 16,
              child: TextButton(
                onPressed: () => unawaited(_openBackup(discover: true)),
                child: const Text('Restore encrypted backup'),
              ),
            ),
          if (_message case final message?)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(message, textAlign: TextAlign.center),
                      if (_needsAuthentication) ...[
                        const SizedBox(height: 8),
                        FilledButton.tonal(
                          onPressed: _authenticating
                              ? null
                              : () => _authenticate(register: false),
                          child: const Text('Authenticate to sync'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    }
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Secure family synchronization',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'Use a passkey to connect this authorized phone. You can add family details after opening the calendar.',
                textAlign: TextAlign.center,
              ),
              if (_message case final message?) ...[
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
              ],
              if (InvitationLinks.token.value != null)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Your invitation is ready. Sign in to review and accept it.',
                  ),
                ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _authenticating
                    ? null
                    : () => _authenticate(register: true),
                child: const Text('Create account with passkey'),
              ),
              TextButton(
                onPressed: _authenticating
                    ? null
                    : () => _authenticate(register: false),
                child: const Text('Use existing passkey'),
              ),
              if (_authenticating) const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
