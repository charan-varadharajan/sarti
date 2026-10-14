import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/core/crypto/resource_crypto.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/core/network/sarti_api.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_controller.dart';
import 'package:sarti_mobile/src/features/sync/sync_engine.dart';
import 'package:sodium/sodium.dart';
import 'package:timezone/data/latest.dart' as tz_data;

const configValue = String.fromEnvironment('SARTI_TEST_SYNC_CONFIG');

void main() {
  test(
    'AAD-HTTP-001 real PostgreSQL reordered vectors preserve conflicts and resolution',
    () async {
      final config = jsonDecode(
        utf8.decode(base64Url.decode(configValue)),
      ) as Map<String, dynamic>;
      tz_data.initializeTimeZones();
      final sodium = await SodiumInit.init();
      final familyId = config['familyId'] as String;
      final calendarId = config['calendarId'] as String;
      final key = sodium.randombytes.buf(32);
      final dbs = <SartiDatabase>[];
      final apis = <SartiApiClient>[];
      final repos = <CalendarRepository>[];
      final engines = <SyncEngine>[];
      final ids = <String>[];
      addTearDown(() {
        for (final api in apis) {
          api.close();
        }
        for (final db in dbs) {
          db.close();
        }
        key.fillRange(0, key.length, 0);
      });
      for (final person in config['devices'] as List) {
        final id = person['device_id'] as String;
        ids.add(id);
        final db = SartiDatabase.open(':memory:', sodium.randombytes.buf(32));
        dbs.add(db);
        db.raw.execute(
          'INSERT INTO households(id, display_name, created_at, calendar_resource_id) VALUES (?, ?, ?, ?)',
          [
            familyId,
            'Prepared family',
            DateTime.now().toUtc().toIso8601String(),
            calendarId,
          ],
        );
        db.setResourceKey(calendarId, 1, key);
        final repo = CalendarRepository(
          db,
          deviceId: id,
          adultId: person['adult_id'] as String,
        );
        repos.add(repo);
        final api = SartiApiClient(
          Uri.parse(config['baseUrl'] as String),
          sessionToken: person['session_token'] as String,
        );
        apis.add(api);
        engines.add(
          SyncEngine(
            database: db,
            repository: repo,
            crypto: ResourceCrypto(sodium),
            sodium: sodium,
            relay: api,
            deviceId: id,
          ),
        );
      }
      final original =
          CalendarController(repos[0], timezone: 'America/Vancouver').save(
            title: 'Prepared activity',
            localStart: DateTime(2026, 10, 12, 9),
            durationMinutes: 60,
            childIds: const [],
          );
      await engines[0].synchronize(familyId);
      await engines[1].synchronize(familyId);
      expect(repos[1].load()!.events.single.title, original.title);
      for (var i = 0; i < 2; i++) {
        CalendarController(repos[i], timezone: 'America/Vancouver').save(
          id: original.id,
          title: i == 0 ? 'First edit' : 'Second edit',
          localStart: original.localStart,
          durationMinutes: 60,
          childIds: const [],
        );
      }
      final pending = dbs[1].raw
          .select("SELECT * FROM outbox WHERE state = 'pending'")
          .single;
      final vector = Map<String, int>.from(
        jsonDecode(pending['vector_json'] as String) as Map,
      );
      expect(vector, hasLength(2));
      final reversedKeys = vector.keys.toList()..sort((a, b) => b.compareTo(a));
      dbs[1].raw.execute(
        'UPDATE outbox SET vector_json = ? WHERE operation_id = ?',
        [
          jsonEncode({for (final k in reversedKeys) k: vector[k]}),
          pending['operation_id'],
        ],
      );
      await engines[0].synchronize(familyId);
      expect((await engines[1].synchronize(familyId)).conflicts, 1);
      expect((await engines[0].synchronize(familyId)).conflicts, 1);
      for (final repo in repos) {
        final conflict = repo.openConflicts().single;
        expect(
          {conflict.local.title, conflict.remote.title},
          {'First edit', 'Second edit'},
        );
      }
      final page = await apis[0].download(familyId, 0);
      final multi = page.operations.singleWhere(
        (e) => e.authorDeviceId == ids[1],
      );
      expect(multi.protocolVersion, 2);
      final sorted = vector.keys.toList()..sort();
      expect(multi.logicalVersion.keys, orderedEquals(sorted));
      expect(multi.logicalVersion.keys, isNot(orderedEquals(reversedKeys)));
      // Replay exact persisted envelope: same receipt, no new operation.
      final saved = jsonDecode(
        dbs[1].raw
                .select('SELECT envelope_json FROM outbox')
                .single['envelope_json']
            as String,
      ) as Map;
      expect(saved['protocolVersion'], 2);
      await apis[1].upload(multi);
      expect(
        (await apis[0].download(familyId, 0)).operations,
        hasLength(page.operations.length),
      );
      repos[1].resolveConflict(
        repos[1].openConflicts().single.id,
        useRemote: true,
      );
      await engines[1].synchronize(familyId);
      await engines[0].synchronize(familyId);
      expect(
        repos[0].load()!.events.single.title,
        repos[1].load()!.events.single.title,
      );
      expect(repos[1].openConflicts(), isEmpty);
      // Remote conflict-card retirement is separately tracked as BUG-017.
      expect(repos[0].openConflicts(), hasLength(1));
      // ADULT-HTTP-001: independent private key, real encrypted upload and
      // owner exclusion enforced by the actual HTTP/PostgreSQL server.
      final adult = CalendarController(repos[1], timezone: 'America/Vancouver');
      addTearDown(adult.dispose);
      final private = adult.save(
        title: 'Private eye exam',
        localStart: DateTime(2026, 10, 13, 17),
        durationMinutes: 60,
        childIds: const [],
        adultAppointment: true,
      );
      await apis[1].provisionResource(
        familyId,
        private.calendarResourceId,
        'personal_calendar',
      );
      dbs[1].setResourceKey(
        private.calendarResourceId,
        1,
        sodium.randombytes.buf(32),
      );
      await engines[1].synchronize(familyId);
      await engines[0].synchronize(familyId);
      expect(
        repos[0].load()!.events.where((e) => e.title == 'Private eye exam'),
        isEmpty,
      );
      expect(dbs[0].resourceKey(private.calendarResourceId, 1), isNull);
      await expectLater(
        apis[0].resourceDevices(familyId, private.calendarResourceId),
        throwsA(
          isA<SartiApiException>().having(
            (e) => e.statusCode,
            'owner access',
            403,
          ),
        ),
      );
      adult.save(
        id: private.id,
        title: 'Shared pickup request',
        localStart: private.localStart,
        durationMinutes: 60,
        childIds: const [],
        adultAppointment: true,
        shareWithHousehold: true,
      );
      await engines[1].synchronize(familyId);
      await engines[0].synchronize(familyId);
      final received = repos[0].load()!.events.singleWhere(
        (e) => e.title == 'Shared pickup request',
      );
      expect(received.id, isNot(private.id));
      expect(received.calendarResourceId, calendarId);
      expect(
        (await apis[0].download(
          familyId,
          0,
        )).operations.every((e) => e.resourceId != private.calendarResourceId),
        isTrue,
      );
    },
    skip: configValue.isEmpty
        ? 'Run via explicit PostgreSQL/HTTP fixture host'
        : false,
  );
}
