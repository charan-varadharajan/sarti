import '../test/support/recovery_confirmation_helper.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sarti_mobile/src/core/crypto/device_key_store.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/features/backup/backup_recovery.dart';
import 'package:sarti_mobile/src/features/backup/backup_screen.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/features/calendar/domain/calendar_event.dart';
import 'package:sodium/sodium.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

// Public BIP-39 vector, used only with disposable synthetic data. Never use this
// phrase for a real family. The host transfers ciphertext, not the database key.
const _phrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const _family = 'portability-family';
const _calendar = 'portability-calendar';
const _transferName = 'backup-portability-transfer.srtbk';

Future<void> _waitFor(File file) async {
  for (var attempt = 0; attempt < 90; attempt++) {
    if (file.existsSync()) return;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  throw StateError('Host transfer did not finish within 90 seconds.');
}

// This scenario isolates native file/cryptography portability from platform
// credential prompts. Physical protected-storage/passkey testing is separate.
class _ScenarioSecrets implements SecretStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
  @override
  Future<void> deleteAll() async => values.clear();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const phase = String.fromEnvironment('BACKUP_PHASE');
  const direction = String.fromEnvironment(
    'BACKUP_DIRECTION',
    defaultValue: 'ios-to-android',
  );
  final reverse = direction == 'android-to-ios';
  final scenario = reverse ? 'BACKUP-XPLAT-002' : 'BACKUP-XPLAT-001';
  testWidgets('$scenario BUG-002 $phase real device backup', (tester) async {
    expect(phase, anyOf('export', 'restore'));
    expect(direction, anyOf('ios-to-android', 'android-to-ios'));
    tz_data.initializeTimeZones();
    final sodium = await SodiumInit.init();
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/backup-portability-scenario');
    if (directory.existsSync()) directory.deleteSync(recursive: true);
    directory.createSync();
    final transfer = File('${support.path}/$_transferName');
    final copied = File('${transfer.path}.copied');
    final ready = File('${support.path}/backup-portability-ready');
    if (copied.existsSync()) copied.deleteSync();
    if (ready.existsSync()) ready.deleteSync();
    final key = Uint8List.fromList(sodium.randombytes.buf(32));
    SartiDatabase? database = SartiDatabase.open(
      '${directory.path}/calendar.db',
      key,
    );
    addTearDown(() {
      database?.close();
      key.fillRange(0, key.length, 0);
      directory.deleteSync(recursive: true);
      // The exporter leaves ciphertext just long enough for the host runner.
      if (transfer.existsSync()) transfer.deleteSync();
      if (copied.existsSync()) copied.deleteSync();
      if (ready.existsSync()) ready.deleteSync();
    });
    final cipherVersion = database.raw
        .select('PRAGMA cipher_version')
        .single
        .values
        .single;
    if (phase == 'export') {
      expect(reverse ? Platform.isAndroid : Platform.isIOS, isTrue);
      if (transfer.existsSync()) transfer.deleteSync();
      final repository = CalendarRepository(
        database,
        deviceId: 'source-${Platform.operatingSystem}',
      );
      final family = repository.createFamily(
        name: 'Portability test family',
        ownerName: 'Synthetic parent',
        familyId: _family,
        calendarResourceId: _calendar,
      );
      repository.addChild(
        'Synthetic child',
        0xFF8E6CEF,
        cloudAlias: 'amber-frog-4821',
      );
      final prepared = repository.load()!;
      repository.saveEvent(
        CalendarEvent(
          id: 'portability-event',
          householdId: _family,
          calendarResourceId: _calendar,
          title: 'Synthetic swimming',
          notes: 'Synthetic note',
          localStart: tz.TZDateTime(
            tz.getLocation('America/Vancouver'),
            2026,
            11,
            3,
            17,
          ),
          timezone: 'America/Vancouver',
          durationMinutes: 45,
          childIds: [prepared.children.single.id],
          pickupGuardianId: family.guardians.single.id,
          reminderMinutes: [15, 30],
          recurrence: const RecurrenceRule(
            frequency: RecurrenceFrequency.weekly,
            weekdays: {2},
          ),
          revision: 1,
          updatedAt: DateTime.utc(2026, 10, 12),
        ),
      );
      database.setResourceKey(
        _calendar,
        1,
        Uint8List.fromList(sodium.randombytes.buf(32)),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: BackupScreen(
            hasBackup: false,
            canCreate: true,
            generatePhrase: () => _phrase,
            create: (phrase) async {
              final bytes = await BackupRecovery.snapshot(
                database: database!,
                key: key,
                phrase: phrase,
                sodium: sodium,
                familyId: _family,
              );
              transfer.writeAsBytesSync(bytes, flush: true);
            },
            restore: (_) async => fail('Export must not restore'),
            remove: () async {},
          ),
        ),
      );
      await tester.tap(find.text('Generate recovery phrase'));
      await tester.pumpAndSettle();
      await confirmFixturePhrase(tester, _phrase);
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Encrypt and upload backup'));
      await tester.tap(find.text('Encrypt and upload backup'));
      await tester.pumpAndSettle();
      expect(find.text('Encrypted backup uploaded.'), findsOneWidget);
      final bytes = transfer.readAsBytesSync();
      expect(bytes.take(5), [83, 65, 82, 84, 2]);
      expect(
        utf8.decode(bytes, allowMalformed: true),
        isNot(contains('Synthetic swimming')),
      );
      binding.reportData = {
        'scenario': scenario,
        'direction': direction,
        'phase': phase,
        'platform': Platform.operatingSystem,
        'sha256': sha256.convert(bytes).toString(),
        'bytes': bytes.length,
        'sqlcipher': cipherVersion,
      };
      // Signal only after the complete encrypted file and UI assertions exist.
      ready.writeAsStringSync('export', flush: true);
      // flutter test removes the app after completion: wait for the host to copy.
      await _waitFor(copied);
    } else {
      expect(reverse ? Platform.isIOS : Platform.isAndroid, isTrue);
      if (transfer.existsSync()) transfer.deleteSync();
      ready.writeAsStringSync('restore', flush: true);
      await _waitFor(copied);
      expect(transfer.existsSync(), isTrue);
      final bytes = transfer.readAsBytesSync();
      const digest = String.fromEnvironment('BACKUP_EXPECTED_SHA256');
      expect(digest, isNotEmpty);
      expect(sha256.convert(bytes).toString(), digest);
      final secrets = _ScenarioSecrets();
      await secrets.write('database-key-v1', base64UrlEncode(key));
      await secrets.write(
        'sign-secret-v1',
        'replacement-${Platform.operatingSystem}-identity',
      );
      var restored = false;
      await tester.pumpWidget(
        MaterialApp(
          home: BackupScreen(
            hasBackup: true,
            canCreate: false,
            generatePhrase: () => _phrase,
            create: (_) async => fail('Restore must not create'),
            remove: () async {},
            restore: (phrase) async {
              final path = database!.path;
              await BackupRecovery.stage(
                blob: bytes,
                phrase: phrase,
                familyId: _family,
                current: database!,
                sodium: sodium,
                secrets: secrets,
              );
              database!.close();
              database = null;
              await BackupRecovery.activate(path, secrets);
              final recoveredKey = base64Url.decode(
                (await secrets.read('database-key-v1'))!,
              );
              try {
                expect(recoveredKey, isNot(orderedEquals(key)));
                database = SartiDatabase.open(path, recoveredKey);
              } finally {
                recoveredKey.fillRange(0, recoveredKey.length, 0);
              }
              restored = true;
            },
          ),
        ),
      );
      // Wrong but valid BIP-39 phrase must not mutate this replacement install.
      await tester.enterText(
        find.byType(TextField),
        'legal winner thank year wave sausage worth useful legal winner thank yellow',
      );
      await tester.tap(find.text('Restore backup'));
      await tester.pumpAndSettle();
      expect(restored, isFalse);
      expect(database!.raw.select('SELECT * FROM households'), isEmpty);
      await tester.enterText(find.byType(TextField), _phrase);
      await tester.tap(find.text('Restore backup'));
      await tester.pumpAndSettle();
      expect(find.text('Backup restored securely.'), findsOneWidget);
      expect(restored, isTrue);
      final family = CalendarRepository(
        database!,
        deviceId: 'replacement-${Platform.operatingSystem}',
      ).load()!;
      expect(family.name, 'Portability test family');
      expect(family.children.single.name, 'Synthetic child');
      expect(family.children.single.colorArgb, 0xFF8E6CEF);
      final event = family.events.single;
      expect(event.title, 'Synthetic swimming');
      expect(event.notes, 'Synthetic note');
      expect(
        event.localStart,
        tz.TZDateTime(tz.getLocation('America/Vancouver'), 2026, 11, 3, 17),
      );
      expect(event.timezone, 'America/Vancouver');
      expect(event.durationMinutes, 45);
      expect(event.childIds, [family.children.single.id]);
      expect(event.pickupGuardianId, family.guardians.single.id);
      expect(event.reminderMinutes, [15, 30]);
      expect(event.recurrence!.frequency, RecurrenceFrequency.weekly);
      expect(event.recurrence!.weekdays, {2});
      expect(
        database!.raw.select('PRAGMA integrity_check').single.values.single,
        'ok',
      );
      expect(database!.raw.select('SELECT * FROM resource_keys'), isEmpty);
      expect(database!.raw.select('SELECT * FROM outbox'), isEmpty);
      expect(
        await secrets.read('sign-secret-v1'),
        'replacement-${Platform.operatingSystem}-identity',
      );
      expect(await secrets.read('backup-recovery-pending-v1'), isNull);
      binding.reportData = {
        'scenario': scenario,
        'direction': direction,
        'phase': phase,
        'platform': Platform.operatingSystem,
        'sha256': digest,
        'bytes': bytes.length,
        'sqlcipher': cipherVersion,
      };
    }
  });
}
