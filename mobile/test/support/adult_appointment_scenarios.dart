import 'dart:convert';
import 'dart:typed_data';

import 'package:sarti_mobile/src/core/crypto/device_key_store.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/core/ids.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:sarti_mobile/src/core/backup/backup_service.dart';
import 'package:sarti_mobile/src/core/crypto/resource_crypto.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/features/backup/backup_recovery.dart';
import 'package:sarti_mobile/src/features/calendar/domain/calendar_event.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_controller.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_screen.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/household_profiles_screen.dart';

import 'child_sync_fixture.dart';

class _PrivateSecrets implements SecretStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
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

void adultAppointmentScenarios() {
  late Sodium sodium;
  setUpAll(() async {
    tz_data.initializeTimeZones();
    sodium = await SodiumInit.init();
  });
  CalendarEvent save(
    CalendarController controller, {
    String? id,
    String title = 'Eye exam',
    bool shared = false,
    List<EventParticipant> participants = const [],
  }) => controller.save(
    id: id,
    title: title,
    localStart: DateTime(2026, 10, 13, 17),
    durationMinutes: 60,
    childIds: const [],
    adultAppointment: true,
    shareWithHousehold: shared,
    participants: participants,
  );
  Future<ChildSyncFixture> prepared() async {
    final f = ChildSyncFixture(sodium, personal: true);
    await f.a.sync();
    await f.b.sync();
    addTearDown(f.close);
    return f;
  }

  testWidgets('ADULT-PRIVATE-001 offline adult save syncs only to the author', (
    tester,
  ) async {
    final f = await prepared();
    final controller = CalendarController(
      f.b.repository,
      timezone: 'America/Vancouver',
    );
    addTearDown(controller.dispose);
    f.offline = true;
    final event = save(controller);
    expect(event.calendarResourceId, isNot(f.calendarId));
    expect(controller.family!.events.single.title, 'Eye exam');
    await expectLater(f.b.sync(), throwsStateError);
    f.offline = false;
    await tester.runAsync(() async {
      await f.b.sync();
      await f.a.sync();
    });
    expect(f.a.repository.load()!.events, isEmpty);
    expect(f.a.database.resourceKey(event.calendarResourceId, 1), isNull);
    expect(
      f.grants
          .where((g) => g.resourceId == event.calendarResourceId)
          .every((g) => g.recipientDeviceId == f.b.id),
      isTrue,
    );
    final envelope = f.operations.singleWhere(
      (e) => e.resourceId == event.calendarResourceId,
    );
    final wrongKey = sodium.secureRandom(32);
    try {
      expect(
        () => ResourceCrypto(sodium).decrypt(
          EncryptedResourcePayload(
            nonce: envelope.nonce,
            ciphertext: envelope.ciphertext,
            additionalData: resourceAdditionalData({
              'protocol': envelope.protocolVersion,
              'familyId': envelope.familyId,
              'resourceId': envelope.resourceId,
              'keyEpoch': envelope.keyEpoch,
              'operationId': envelope.operationId,
              'authorDeviceId': envelope.authorDeviceId,
              'deviceSequence': envelope.deviceSequence,
              'logicalVersion': envelope.logicalVersion,
            }),
          ),
          wrongKey,
        ),
        throwsA(anything),
      );
    } finally {
      wrongKey.dispose();
    }
  });

  testWidgets(
    'ADULT-SHARE-001 confirmed household copy is distinct and unsharing tombstones it',
    (tester) async {
      final f = await prepared();
      final controller = CalendarController(
        f.b.repository,
        timezone: 'America/Vancouver',
      );
      addTearDown(controller.dispose);
      final private = save(controller);
      expect(f.b.repository.isShared(private.id), isFalse);
      save(controller, id: private.id, shared: true);
      await tester.runAsync(() async {
        await f.b.sync();
        await f.a.sync();
      });
      final received = f.a.repository.load()!.events.single;
      expect(received.title, 'Eye exam');
      expect(received.id, isNot(private.id));
      expect(received.calendarResourceId, f.calendarId);
      expect(f.b.repository.load()!.events, hasLength(1));
      final sharedPayload = f.b.database.raw.select(
        'SELECT payload_json FROM outbox WHERE resource_id=?',
        [f.calendarId],
      );
      expect(
        sharedPayload.every(
          (r) => !(r['payload_json'] as String).contains(private.id),
        ),
        isTrue,
      );
      save(controller, id: private.id, shared: false);
      await tester.runAsync(() async {
        await f.b.sync();
        await f.a.sync();
      });
      expect(f.a.repository.load()!.events, isEmpty);
      expect(f.b.repository.load()!.events.single.title, 'Eye exam');
    },
  );

  testWidgets(
    'ADULT-CONFLICT-001 household edits cannot silently overwrite private or shared versions',
    (tester) async {
      final f = await prepared();
      final controller = CalendarController(
        f.b.repository,
        timezone: 'America/Vancouver',
      );
      addTearDown(controller.dispose);
      final private = save(controller, shared: true);
      await tester.runAsync(() async {
        await f.b.sync();
        await f.a.sync();
      });
      final shared = f.a.repository.load()!.events.single;
      f.a.repository.saveEvent(
        shared.copyWith(title: 'Household changed pickup', revision: 2),
      );
      await tester.runAsync(() async {
        await f.a.sync();
        await f.b.sync();
      });
      expect(
        () => save(
          controller,
          id: private.id,
          title: 'New private draft',
          shared: true,
        ),
        throwsStateError,
      );
      expect(f.b.repository.load()!.events.single.title, 'Eye exam');
      expect(
        f.b.database.raw.select('SELECT title FROM events WHERE id=?', [
          shared.id,
        ]).single['title'],
        'Household changed pickup',
      );
      final reviewed = f.b.repository.householdCopy(private.id)!;
      f.b.repository.saveAdultAppointment(
        private.copyWith(title: 'Confirmed preview', revision: 3),
        share: true,
        reviewedSharedVector: reviewed.vector,
      );
      expect(f.b.repository.load()!.events.single.title, 'Confirmed preview');
      expect(
        f.b.repository.householdCopy(private.id)!.event.title,
        'Confirmed preview',
      );
    },
  );

  testWidgets(
    'PET-CAL-001 pet appointment and profile colour survive encrypted sync',
    (tester) async {
      final f = await prepared();
      final pet = f.a.repository.saveParticipant(
        name: 'Pepper',
        kind: 'pet',
        colour: 0xffc5e1c1,
      );
      final controller = CalendarController(
        f.a.repository,
        timezone: 'America/Vancouver',
      );
      addTearDown(controller.dispose);
      controller.refresh();
      controller.save(
        title: 'Vet',
        localStart: DateTime(2026, 10, 13, 12),
        durationMinutes: 60,
        childIds: [],
        participants: [EventParticipant(id: pet.id, kind: 'pet')],
      );
      await tester.runAsync(() async {
        await f.a.sync();
        await f.b.sync();
      });
      final receiving = f.b.repository.load()!;
      expect(receiving.participants.single.name, 'Pepper');
      expect(receiving.participants.single.colorArgb, 0xffc5e1c1);
      expect(receiving.events.single.participants.single.id, pet.id);
      final decoded = CalendarEvent.fromJson(receiving.events.single.toJson());
      expect(decoded.participants.single.kind, 'pet');
    },
  );

  testWidgets(
    'PROFILE-COLOUR-001 prepared adult editor saves a pastel profile',
    (tester) async {
      final f = await prepared();
      final controller = CalendarController(
        f.b.repository,
        timezone: 'America/Vancouver',
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(home: HouseholdProfilesScreen(controller: controller)),
      );
      await tester.tap(find.byKey(const Key('my-profile')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('profile-name')), 'Alex');
      await tester.tap(find.text('Pastel colour'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile-colour-rose')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile-save')));
      await tester.pumpAndSettle();
      expect(f.b.repository.load()!.participants.single.colorArgb, 0xfff3bfd1);
      await tester.runAsync(() async {
        await f.b.sync();
        await f.a.sync();
      });
      expect(f.a.repository.load()!.participants.single.name, 'Alex');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'ADULT-UI-001 prepared calendar saves an adult appointment privately by default',
    (tester) async {
      final f = await prepared();
      final controller = CalendarController(
        f.b.repository,
        timezone: 'America/Vancouver',
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(home: CalendarScreen(controller: controller)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Eye exam');
      final toggle = find.byKey(const Key('adult-appointment'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        controller.family!.events.single.calendarResourceId,
        f.b.repository.personalResourceId,
      );
      expect(
        f.b.repository.isShared(controller.family!.events.single.id),
        isFalse,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('ADULT-RECOVERY-001 family snapshot excludes private content; private snapshot validates recovery', () async {
    final f = await prepared();
    final controller = CalendarController(
      f.a.repository,
      timezone: 'America/Vancouver',
    );
    addTearDown(controller.dispose);
    final event = save(controller, title: 'Private clinical notes');
    final phrase = BackupService.generateRecoveryPhrase(sodium: sodium);
    final key = f.a.keys.databaseKey.extractBytes();
    final dir = Directory.systemTemp.createTempSync('sarti-private-test-');
    addTearDown(() => dir.deleteSync(recursive: true));
    Future<SartiDatabase> snapshot(String name, {String? adult}) async {
      final bytes = await BackupRecovery.snapshot(
        database: f.a.database,
        key: key,
        phrase: phrase,
        sodium: sodium,
        familyId: f.familyId,
        adultId: adult,
      );
      final file = File('${dir.path}/$name.srtbk')..writeAsBytesSync(bytes);
      final result = BackupService.restoreBackup(
        backupPath: file.path,
        outputPath: '${dir.path}/$name.db',
        recoveryPhrase: phrase,
        sodium: sodium,
      );
      final db = SartiDatabase.open('${dir.path}/$name.db', result.databaseKey);
      result.databaseKey.fillRange(0, 32, 0);
      return db;
    }

    final family = await snapshot('family');
    try {
      expect(
        family.raw.select('SELECT 1 FROM events WHERE id=?', [event.id]),
        isEmpty,
      );
      expect(family.raw.select('SELECT 1 FROM personal_calendars'), isEmpty);
      expect(
        family.raw.select('SELECT 1 FROM outbox WHERE resource_id=?', [
          event.calendarResourceId,
        ]),
        isEmpty,
      );
    } finally {
      family.close();
    }
    final personal = await snapshot('personal', adult: f.a.repository.adultId);
    try {
      expect(
        personal.raw.select('SELECT title FROM events').single['title'],
        'Private clinical notes',
      );
    } finally {
      personal.close();
    }
    final wrong = BackupService.generateRecoveryPhrase(sodium: sodium);
    expect(
      () => BackupService.restoreBackup(
        backupPath: '${dir.path}/personal.srtbk',
        outputPath: '${dir.path}/wrong.db',
        recoveryPhrase: wrong,
        sodium: sodium,
      ),
      throwsA(isA<BackupException>()),
    );
    final corrupt = File('${dir.path}/personal.srtbk');
    final data = corrupt.readAsBytesSync();
    data[data.length - 1] ^= 1;
    corrupt.writeAsBytesSync(data);
    expect(
      () => BackupService.restoreBackup(
        backupPath: corrupt.path,
        outputPath: '${dir.path}/bad.db',
        recoveryPhrase: phrase,
        sodium: sodium,
      ),
      throwsA(isA<BackupException>()),
    );
    key.fillRange(0, key.length, 0);
  });
  test(
    'ADULT-DRAFT-001 offline draft binds only once to an authenticated adult',
    () {
      final f = ChildSyncFixture(sodium);
      addTearDown(f.close);
      final controller = CalendarController(
        f.a.repository,
        timezone: 'America/Vancouver',
      );
      addTearDown(controller.dispose);
      final event = save(controller, title: 'Offline private draft');
      final local = f.a.repository.currentAdultId;
      expect(local, isNotNull);
      final authenticated = newId();
      final bound = CalendarRepository(
        f.a.database,
        deviceId: f.a.id,
        adultId: authenticated,
      );
      expect(bound.load()!.events.single.title, 'Offline private draft');
      expect(bound.personalResourceId, event.calendarResourceId);
      expect(
        f.a.database.raw
            .select('SELECT adult_id FROM personal_calendars')
            .single['adult_id'],
        authenticated,
      );
      final other = CalendarRepository(
        f.a.database,
        deviceId: f.a.id,
        adultId: newId(),
      );
      expect(other.load()!.events, isEmpty);
    },
  );

  test('ADULT-RECOVERY-002 wrong adult is rejected; correct phrase stages and activates a private snapshot', () async {
    final f = await prepared();
    final controller = CalendarController(
      f.b.repository,
      timezone: 'America/Vancouver',
    );
    addTearDown(controller.dispose);
    final original = save(controller, title: 'Private eye exam');
    await f.b.sync();
    save(controller, id: original.id, title: 'Private eye exam final draft');
    final phrase = BackupService.generateRecoveryPhrase(sodium: sodium);
    final sourceKey = f.b.keys.databaseKey.extractBytes();
    final bytes = await BackupRecovery.snapshot(
      database: f.b.database,
      key: sourceKey,
      phrase: phrase,
      sodium: sodium,
      familyId: f.familyId,
      adultId: f.b.repository.adultId,
    );
    sourceKey.fillRange(0, sourceKey.length, 0);
    final dir = Directory.systemTemp.createTempSync('sarti-personal-restore-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/target.db';
    final target = SartiDatabase.open(path, Uint8List(32));
    final secrets = _PrivateSecrets();
    secrets.values['new-device-signing'] = 'preserve';
    await expectLater(
      BackupRecovery.stage(
        blob: bytes,
        phrase: phrase,
        familyId: f.familyId,
        current: target,
        sodium: sodium,
        secrets: secrets,
        adultId: f.a.repository.adultId,
      ),
      throwsA(isA<BackupException>()),
    );
    expect(target.raw.select('SELECT 1 FROM households'), isEmpty);
    expect(secrets.values.containsKey('backup-recovery-pending-v1'), isFalse);
    await BackupRecovery.stage(
      blob: bytes,
      phrase: phrase,
      familyId: f.familyId,
      current: target,
      sodium: sodium,
      secrets: secrets,
      adultId: f.b.repository.adultId,
    );
    target.close();
    await BackupRecovery.activate(path, secrets);
    final restoredKey = base64Url.decode(secrets.values['database-key-v1']!);
    final restored = SartiDatabase.open(path, restoredKey);
    try {
      expect(
        CalendarRepository(
          restored,
          deviceId: newId(),
          adultId: f.b.repository.adultId,
        ).load()!.events.single.title,
        'Private eye exam final draft',
      );
      expect(
        restored.resourceKey(controller.repository.personalResourceId!, 1),
        isNotNull,
      );
      expect(restored.raw.select('SELECT 1 FROM event_versions'), isNotEmpty);
      expect(restored.raw.select('SELECT 1 FROM outbox'), isEmpty);
      final recovered = CalendarRepository(
        restored,
        deviceId: newId(),
        adultId: f.b.repository.adultId,
      );
      expect(
        recovered.applyRemote(
          operationId: newId(),
          event: original,
          vector: {f.b.id: 1},
        ),
        RemoteApplyResult.stale,
      );
      expect(
        recovered.load()!.events.single.title,
        'Private eye exam final draft',
      );
      expect(secrets.values['new-device-signing'], 'preserve');
    } finally {
      restored.close();
      restoredKey.fillRange(0, restoredKey.length, 0);
    }
  });
  testWidgets(
    'PROFILE-CHILD-001 explicit legacy child recolouring syncs without upgrade recolouring',
    (tester) async {
      final f = await prepared();
      final child = f.a.repository.addChild(
        'Mia legacy',
        0xff1565c0,
        shareWithCalendarGuardians: true,
      );
      await tester.runAsync(() async {
        await f.a.sync();
        await f.b.sync();
      });
      expect(f.b.repository.load()!.children.single.colorArgb, 0xff1565c0);
      final controller = CalendarController(
        f.a.repository,
        timezone: 'America/Vancouver',
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(home: HouseholdProfilesScreen(controller: controller)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mia legacy'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile-colour-rose')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await f.a.sync();
        await f.b.sync();
      });
      expect(f.b.repository.load()!.children.single.colorArgb, 0xfff3bfd1);
      expect(f.b.repository.load()!.children.single.id, child.id);
      expect(f.b.repository.load()!.children.single.name, 'Mia legacy');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
