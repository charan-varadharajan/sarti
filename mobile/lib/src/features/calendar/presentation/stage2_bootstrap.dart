import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sarti_mobile/src/core/crypto/device_key_store.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/features/calendar/data/reminder_scheduler.dart';
import 'package:sarti_mobile/src/features/sync/authenticated_calendar_bootstrap.dart';
import 'package:sodium/sodium.dart';
import 'package:timezone/data/latest.dart' as tz_data;

class Stage2Bootstrap extends StatefulWidget {
  const Stage2Bootstrap({super.key});

  @override
  State<Stage2Bootstrap> createState() => _Stage2BootstrapState();
}

class _Stage2BootstrapState extends State<Stage2Bootstrap> {
  SartiDatabase? _database;
  DeviceKeyMaterial? _keys;
  late final Future<_LocalResources> _resources = _open();

  Future<_LocalResources> _open() async {
    tz_data.initializeTimeZones();
    final sodium = await SodiumInit.init();
    final secrets = PlatformSecretStore();
    final keys = await DeviceKeyStore(
      sodium,
      secrets,
      PlatformDeviceUnlock(),
    ).loadOrCreate();
    final directory = await getApplicationSupportDirectory();
    final database = SartiDatabase.open(
      '${directory.path}${Platform.pathSeparator}sarti.db',
      keys.databaseKey.extractBytes(),
    );
    _database = database;
    _keys = keys;
    final reminders = LocalReminderScheduler();
    await reminders.initialize();
    const timezone = String.fromEnvironment(
      'SARTI_TIMEZONE',
      defaultValue: 'America/Vancouver',
    );
    return _LocalResources(
      database: database,
      keys: keys,
      sodium: sodium,
      secrets: secrets,
      reminders: reminders,
      timezone: timezone,
    );
  }

  @override
  void dispose() {
    _database?.close();
    _keys?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_LocalResources>(
    future: _resources,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Sarti could not unlock encrypted local storage.\n${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final resources = snapshot.requireData;
      return AuthenticatedCalendarBootstrap(
        database: resources.database,
        keys: resources.keys,
        sodium: resources.sodium,
        secrets: resources.secrets,
        reminders: resources.reminders,
        timezone: resources.timezone,
      );
    },
  );
}

class _LocalResources {
  const _LocalResources({
    required this.database,
    required this.keys,
    required this.sodium,
    required this.secrets,
    required this.reminders,
    required this.timezone,
  });

  final SartiDatabase database;
  final DeviceKeyMaterial keys;
  final Sodium sodium;
  final SecretStore secrets;
  final ReminderScheduler reminders;
  final String timezone;
}
