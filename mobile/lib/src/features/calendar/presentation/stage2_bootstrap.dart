import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sarti_mobile/src/core/crypto/device_key_store.dart';
import 'package:sarti_mobile/src/core/crypto/resource_crypto.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/features/ai/cloud_ai_consent.dart';
import 'package:sarti_mobile/src/features/ai/native_ai_provider.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/features/calendar/data/reminder_scheduler.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_controller.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_screen.dart';
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
  late final Future<CalendarController> _controller = _open();

  Future<CalendarController> _open() async {
    tz_data.initializeTimeZones();
    final sodium = await SodiumInit.init();
    final keys = await DeviceKeyStore(
      sodium,
      PlatformSecretStore(),
      PlatformDeviceUnlock(),
    ).loadOrCreate();
    final directory = await getApplicationSupportDirectory();
    final database = SartiDatabase.open(
      '${directory.path}${Platform.pathSeparator}sarti.db',
      keys.databaseKey.extractBytes(),
    );
    _database = database;
    _keys = keys;
    final repository = CalendarRepository(database, deviceId: keys.deviceId);
    final reminders = LocalReminderScheduler();
    await reminders.initialize();
    const timezone = String.fromEnvironment(
      'SARTI_TIMEZONE',
      defaultValue: 'America/Vancouver',
    );
    return CalendarController(
      repository,
      timezone: timezone,
      reminders: reminders,
      onFamilyCreated: (family) {
        final key = ResourceCrypto(sodium).newResourceKey();
        try {
          database.setResourceKey(
            family.calendarResourceId,
            1,
            key.extractBytes(),
          );
        } finally {
          key.dispose();
        }
      },
    );
  }

  @override
  void dispose() {
    _database?.close();
    _keys?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<CalendarController>(
    future: _controller,
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
      final database = _database!;
      return CalendarScreen(
        controller: snapshot.requireData,
        nativeAi: NativeEventAiProvider(),
        cloudAiConsent: CloudAiConsentController(CloudAiConsentStore(database)),
      );
    },
  );
}
