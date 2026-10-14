import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/core/backup/backup_service.dart';
import 'package:sarti_mobile/src/core/crypto/device_key_store.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/features/backup/backup_recovery.dart';
import 'package:sodium/sodium.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/features/calendar/domain/calendar_event.dart';

class MemorySecrets implements SecretStore {
  final values = <String, String>{};
  bool failWrite = false;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    if (failWrite) throw StateError('protected storage unavailable');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    values.clear();
  }
}

void main() {
  const phrase =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
  late Sodium sodium;
  late Directory dir;
  late SartiDatabase source;
  late SartiDatabase target;
  late Uint8List originalKey;
  late MemorySecrets secrets;
  setUpAll(() async {
    tz_data.initializeTimeZones();
    sodium = await SodiumInit.init();
  });
  setUp(() {
    dir = Directory.systemTemp.createTempSync('sarti-backup-test-');
    originalKey = Uint8List.fromList(List.filled(32, 37));
    source = SartiDatabase.open('${dir.path}/source.db', originalKey);
    source.raw.execute('INSERT INTO households VALUES (?, ?, ?, ?)', [
      'family-a',
      'Synthetic family',
      '2026-01-01',
      'calendar-a',
    ]);
    source.setResourceKey('calendar-a', 1, Uint8List(32));
    CalendarRepository(source, deviceId: 'old-device').saveEvent(
      CalendarEvent(
        id: 'event-a',
        householdId: 'family-a',
        calendarResourceId: 'calendar-a',
        title: 'Synthetic swimming',
        localStart: DateTime(2026, 10, 13, 17),
        timezone: 'America/Vancouver',
        durationMinutes: 60,
        childIds: [],
        recurrence: const RecurrenceRule(frequency: RecurrenceFrequency.weekly),
        revision: 1,
        updatedAt: DateTime.utc(2026, 10, 12),
      ),
    );
    target = SartiDatabase.open('${dir.path}/target.db', Uint8List(32));
    secrets = MemorySecrets();
    secrets.values['database-key-v1'] = base64UrlEncode(Uint8List(32));
    secrets.values['sign-secret-v1'] = 'new-device-private-key';
  });
  tearDown(() {
    source.close();
    target.close();
    dir.deleteSync(recursive: true);
  });
  Future<Uint8List> snapshot() => BackupRecovery.snapshot(
    database: source,
    key: originalKey,
    phrase: phrase,
    sodium: sodium,
    familyId: 'family-a',
  );
  Future<void> stage(
    Uint8List blob, {
    String family = 'family-a',
    String recoveryPhrase = phrase,
  }) => BackupRecovery.stage(
    blob: blob,
    phrase: recoveryPhrase,
    familyId: family,
    current: target,
    sodium: sodium,
    secrets: secrets,
  );

  test(
    'BACKUP-MOB-002 BUG-002 replacement install restores using recovered key',
    () async {
      final blob = await snapshot();
      expect(
        utf8.decode(blob, allowMalformed: true),
        isNot(contains('Synthetic family')),
      );
      expect(blob.sublist(0, 5), [83, 65, 82, 84, 2]);
      await stage(blob);
      expect(target.raw.select('SELECT * FROM households'), isEmpty);
      final path = target.path;
      // A replacement installation starts with an independently generated key.
      await BackupRecovery.activate(path, secrets);
      final recovered = base64Url.decode(secrets.values['database-key-v1']!);
      expect(recovered, hasLength(32));
      expect(recovered, isNot(originalKey));
      final db = SartiDatabase.open(path, recovered);
      expect(
        db.raw
            .select('SELECT display_name FROM households')
            .single['display_name'],
        'Synthetic family',
      );
      final event = CalendarRepository(
        db,
        deviceId: 'new-device',
      ).load()!.events.single;
      expect(event.title, 'Synthetic swimming');
      expect(event.recurrence!.frequency, RecurrenceFrequency.weekly);
      expect(db.raw.select('SELECT * FROM outbox'), isEmpty);
      expect(db.raw.select('SELECT * FROM resource_keys'), isEmpty);
      db.close();
      expect(secrets.values['sign-secret-v1'], 'new-device-private-key');
      expect(secrets.values.containsKey('backup-recovery-pending-v1'), isFalse);
      await BackupRecovery.activate(path, secrets); // idempotent retry
    },
  );
  test('family mismatch leaves current database and key untouched', () async {
    await expectLater(
      stage(await snapshot(), family: 'family-b'),
      throwsA(isA<BackupException>()),
    );
    expect(secrets.values['database-key-v1'], base64UrlEncode(Uint8List(32)));
    expect(File('${target.path}.recovery').existsSync(), isFalse);
  });
  test('protected storage failure never activates staged database', () async {
    final blob = await snapshot();
    secrets.failWrite = true;
    await expectLater(stage(blob), throwsStateError);
    expect(target.raw.select('SELECT * FROM households'), isEmpty);
    expect(File('${target.path}.recovery').existsSync(), isFalse);
  });
  test('activation retries after protected storage fails', () async {
    await stage(await snapshot());
    final stagedKey = secrets.values['backup-recovery-pending-v1'];
    secrets.failWrite = true;
    await expectLater(
      BackupRecovery.activate(target.path, secrets),
      throwsStateError,
    );
    expect(File('${target.path}.recovery').existsSync(), isTrue);
    secrets.failWrite = false;
    await BackupRecovery.activate(target.path, secrets);
    expect(secrets.values['database-key-v1'], stagedKey);
  });
  test('existing local calendar cannot be overwritten', () async {
    target.raw.execute('INSERT INTO households VALUES (?, ?, ?, ?)', [
      'local-family',
      'Offline data',
      '2026-01-01',
      'local-calendar',
    ]);
    await expectLater(stage(await snapshot()), throwsA(isA<BackupException>()));
    expect(
      target.raw
          .select('SELECT display_name FROM households')
          .single['display_name'],
      'Offline data',
    );
    expect(secrets.values.length, 2);
  });
  test('pending recovery cannot be replaced before activation', () async {
    final blob = await snapshot();
    await stage(blob);
    final journal = secrets.values['backup-recovery-pending-v1'];
    await expectLater(stage(blob), throwsA(isA<BackupException>()));
    expect(secrets.values['backup-recovery-pending-v1'], journal);
    expect(File('${target.path}.recovery').existsSync(), isTrue);
    await BackupRecovery.activate(target.path, secrets);
    expect(secrets.values['database-key-v1'], journal);
  });
  test('wrong phrase cannot stage data or change secrets', () async {
    await expectLater(
      stage(
        await snapshot(),
        recoveryPhrase: 'legal winner thank year wave sausage worth useful legal winner thank yellow',
      ),
      throwsA(isA<BackupException>()),
    );
    expect(File('${target.path}.recovery').existsSync(), isFalse);
    expect(secrets.values.length, 2);
  });
}
