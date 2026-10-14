import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/core/ids.dart';
import 'package:sarti_mobile/src/core/network/sarti_api.dart';
import 'package:sarti_mobile/src/features/ai/event_parser.dart';
import 'package:sarti_mobile/src/features/ai/cloud_ai_consent.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_screen.dart';
import 'package:sarti_mobile/src/features/ai/native_ai_provider.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/features/calendar/domain/calendar_event.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_controller.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/family_management_screen.dart';
import 'package:timezone/data/latest.dart' as zones;

import 'child_sync_fixture.dart';
import 'sarti_test_harness.dart';
import 'profile_navigation_scenarios.dart';

class UnavailableTestAi implements NativeAiBridge {
  @override
  Future<NativeAiAvailability> availability() async =>
      NativeAiAvailability.unsupported;
  @override
  Future<String> generate(String prompt) async =>
      throw StateError('No native model');
}

class FixtureCloudApi extends SartiApiClient {
  FixtureCloudApi()
    : super(Uri.parse('https://fixture.invalid'), sessionToken: 'synthetic');
  final requests = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> cloudCapability() async => {
    'available': true,
    'consent_version': 3,
  };
  @override
  Future<Map<String, dynamic>> cloudProposal(
    Map<String, dynamic> payload,
  ) async {
    requests.add(payload);
    return {'timeHour': 12, 'timeMinute': 0};
  }
}

void remainingBugScenarios() {
  profileNavigationScenarios();
  setUpAll(zones.initializeTimeZones);
  test('NLP-BATCH-001 distinct clocks retain both child proposals and shared explicit context', () {
    final proposals = const DeterministicEventParser().parseAll(
      'Tomorrow karate for Mia at 5 pm and Jithu at 7 pm',
      now: DateTime(2026, 10, 14),
    );
    expect(proposals, hasLength(2));
    expect(proposals.map((p) => p.title), ['karate', 'karate']);
    expect(proposals.map((p) => p.timeOfDay!.hour), [17, 19]);
    expect(proposals.map((p) => p.date), everyElement(DateTime(2026, 10, 15)));
    expect(proposals[0].childNameTokens, ['Mia']);
    expect(proposals[1].childNameTokens, ['Jithu']);
    final shared = const DeterministicEventParser().parseAll(
      'Mia and Jithu have swimming tomorrow at 5pm',
    );
    expect(shared, hasLength(1));
    expect(shared.single.childNameTokens, containsAll(['Mia', 'Jithu']));
  });
  test('NLP-DURATION-001 noon, explicit duration, range and ambiguity', () {
    const parser = DeterministicEventParser();
    final p = parser.parse('mia has swimming for 2 hours tomorrow at noon');
    expect(p.title, 'swimming');
    expect(p.timeOfDay!.hour, 12);
    expect(p.durationMinutes, 120);
    expect(parser.parse('Swim tomorrow at midnight').timeOfDay!.hour, 0);
    expect(parser.parse('Swim from 5pm to 7pm tomorrow').durationMinutes, 120);
    expect(
      parser
          .parse('Swim for 1 hour from 5pm to 7pm tomorrow')
          .requiresDurationConfirmation,
      isTrue,
    );
    expect(
      parser
          .parse('Swim for 0 hours tomorrow at noon')
          .requiresDurationConfirmation,
      isTrue,
    );
    expect(parser.parse('Swim at 13pm').timeOfDay, isNull);
    expect(parser.parse('Swim at 5 and 7pm').requiresTimeConfirmation, isTrue);
  });
  testWidgets(
    'NLP-BATCH-MOB-001 prepared review edits durations and saves atomically only after final approval',
    (tester) async {
      final f = SartiTestHarness.create();
      addTearDown(f.close);
      await f.pumpCalendar(
        tester,
        nativeAi: NativeEventAiProvider(UnavailableTestAi()),
      );
      await f.openNaturalLanguageEvent(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Event description'),
        'Tomorrow karate for Mia at 5 pm and Jithu at 7 pm',
      );
      await tester.pump();
      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();
      expect(find.text('Review suggestion 1 of 2'), findsOneWidget);
      expect(find.text('Default: 1 hour'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('proposal-duration-hours')),
        '2',
      );
      await tester.tap(find.text('Review next'));
      await tester.pumpAndSettle();
      expect(f.repository.load()!.events, isEmpty);
      expect(find.text('Review suggestion 2 of 2'), findsOneWidget);
      await tester.tap(find.text('Add 2 to calendar'));
      await tester.pumpAndSettle();
      final events = f.repository.load()!.events;
      expect(events, hasLength(2));
      expect(events.map((e) => e.durationMinutes), [120, 60]);
      expect(events.map((e) => e.localStart.hour), [17, 19]);
      expect(events[0].childIds.single, isNot(events[1].childIds.single));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'NLP-DST-MOB-001 end-time range uses elapsed DST duration and conflicting explicit duration needs review',
    (tester) async {
      final f = SartiTestHarness.create(
        clock: () => DateTime.utc(2026, 3, 8, 8),
      );
      addTearDown(f.close);
      await f.pumpCalendar(
        tester,
        nativeAi: NativeEventAiProvider(UnavailableTestAi()),
      );
      Future<void> preview(String text) async {
        await f.openNaturalLanguageEvent(tester);
        await tester.enterText(
          find.widgetWithText(TextField, 'Event description'),
          text,
        );
        await tester.pump();
        await tester.tap(find.text('Preview'));
        await tester.pumpAndSettle();
      }

      await preview('Mia has swimming today from 1:30am to 3:30am');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('proposal-duration-hours')))
            .controller!
            .text,
        '1',
      );
      expect(find.textContaining('3:30 AM PDT'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await preview('Mia has swimming for 2 hours today from 1:30am to 3:30am');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('proposal-duration')))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Add to calendar'),
            )
            .onPressed,
        isNull,
      );
      expect(f.repository.load()!.events, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'UNDO-MOB-001 Undo previews without mutation; dirty save, revert and cancel preserve event',
    (tester) async {
      final f = SartiTestHarness.create();
      addTearDown(f.close);
      await f.pumpCalendar(
        tester,
        nativeAi: NativeEventAiProvider(UnavailableTestAi()),
      );
      await f.openNaturalLanguageEvent(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Event description'),
        'Mia has swimming for 2 hours tomorrow at noon',
      );
      await tester.pump();
      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();
      expect(find.text('Ends: 2:00 PM'), findsOneWidget);
      await tester.tap(find.text('Add to calendar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(f.repository.load()!.events.single.durationMinutes, 120);
      final save = find.widgetWithText(FilledButton, 'Save');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'Changed',
      );
      await tester.pump();
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'swimming',
      );
      await tester.pump();
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(f.repository.load()!.events.single.title, 'swimming');
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'FAMILY-HUB-MOB-001 prepared family admin edits names; offline guardian route explained',
    (tester) async {
      final f = SartiTestHarness.create();
      addTearDown(f.close);
      await tester.pumpWidget(
        MaterialApp(home: FamilyManagementScreen(controller: f.controller)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Connect and sign in'), findsOneWidget);
      await tester.tap(find.text('Test family'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('family-edit-name')),
        'Edited family',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(f.controller.family!.name, 'Edited family');
      await tester.tap(find.text('Mia'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('family-edit-name')),
        'Mia new',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        f.controller.family!.children.map((c) => c.name),
        contains('Mia new'),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  test('FAMILY-HUB-SYNC-001 names cross encrypted profile channel and guardian mutations denied', () async {
    final f = ChildSyncFixture(await SodiumInit.init());
    addTearDown(f.close);
    final profile = newId();
    f.childPermissions[profile] = 'read';
    f.resources[profile] = RemoteResource(
      id: profile,
      kind: 'family_profile',
      keyEpoch: 1,
    );
    final owner = CalendarController(f.a.repository, timezone: 'Etc/UTC');
    addTearDown(owner.dispose);
    final guardianId = owner.family!.guardians.single.id;
    owner.saveFamilyDetails('Updated household', {
      guardianId: 'Updated parent',
    });
    await f.a.sync();
    await f.b.sync();
    expect(f.b.repository.load()!.name, 'Updated household');
    expect(f.b.repository.load()!.guardians.single.name, 'Updated parent');
    expect(f.operations.where((e) => e.resourceId == profile), isNotEmpty);
    f.b.database.raw.execute(
      'INSERT OR REPLACE INTO app_preferences VALUES (?,?)',
      [
        'family-access-${f.familyId}',
        jsonEncode({'role': 'guardian', 'permission': 'read'}),
      ],
    );
    final guardian = CalendarController(f.b.repository, timezone: 'Etc/UTC');
    addTearDown(guardian.dispose);
    expect(
      () => guardian.saveFamilyDetails('Unauthorized', {}),
      throwsStateError,
    );
    expect(() => owner.renameChild(newId(), 'Foreign'), throwsArgumentError);
  });
  testWidgets(
    'CLOUD-BROKER-MOB-001 cloud action is explicit, minimized and cannot save an event',
    (tester) async {
      final f = SartiTestHarness.create();
      addTearDown(f.close);
      final api = FixtureCloudApi();
      addTearDown(api.close);
      final consent = CloudAiConsentController(CloudAiConsentStore(f.database));
      addTearDown(consent.dispose);
      consent.setEnabled(true);
      await tester.pumpWidget(
        MaterialApp(
          home: CalendarScreen(
            controller: f.controller,
            nativeAi: NativeEventAiProvider(UnavailableTestAi()),
            cloudApi: api,
            cloudAiConsent: consent,
          ),
        ),
      );
      await f.openNaturalLanguageEvent(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Event description'),
        'Mia has swimming tomorrow at noon',
      );
      await tester.pump();
      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();
      expect(api.requests, isEmpty);
      expect(f.repository.load()!.events, isEmpty);
      await tester.tap(find.text('Use cloud assist'));
      await tester.pumpAndSettle();
      expect(api.requests, hasLength(1));
      final payload = jsonEncode(api.requests.single);
      expect(payload, isNot(contains('Mia')));
      expect(payload, isNot(contains('hanging-frog')));
      expect(api.requests.single.keys.toSet(), {'version', 'tokens'});
      expect(f.repository.load()!.events, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );
  test('NLP-BATCH-SEC-001 invalid second event rolls back all local rows and outbox', () {
    final db = SartiDatabase.open(':memory:', Uint8List(32));
    addTearDown(db.close);
    final repo = CalendarRepository(db, deviceId: newId());
    final family = repo.createFamily();
    final foreign = newId(), child = newId();
    db.raw.execute(
      'INSERT INTO households(id,display_name,created_at,calendar_resource_id) VALUES (?,?,?,?)',
      [foreign, 'Other', '2026-10-14', newId()],
    );
    db.raw.execute(
      'INSERT INTO children(id,household_id,display_name,color_argb,cloud_alias) VALUES (?,?,?,?,?)',
      [child, foreign, 'Other', 0xffccddee, 'opaque-123'],
    );
    final event = CalendarEvent(
      id: newId(),
      householdId: family.householdId,
      calendarResourceId: family.calendarResourceId,
      title: 'First',
      localStart: DateTime(2026, 10, 15),
      timezone: 'Etc/UTC',
      durationMinutes: 60,
      childIds: [],
      revision: 1,
      updatedAt: DateTime.utc(2026),
    );
    expect(
      () => repo.saveReviewedEvents([
        event,
        event.copyWith(id: newId(), childIds: [child]),
      ]),
      throwsStateError,
    );
    expect(db.raw.select('SELECT * FROM events'), isEmpty);
    expect(
      db.raw.select("SELECT * FROM outbox WHERE kind='event_upserted'"),
      isEmpty,
    );
  });
  test('CONFLICT-RETIRE-001 merged remote resolution retires only covered event; stale action cannot write', () {
    final db = SartiDatabase.open(':memory:', Uint8List(32));
    addTearDown(db.close);
    final a = newId(), b = newId();
    final repo = CalendarRepository(db, deviceId: a);
    final family = repo.createFamily();
    CalendarEvent event(String id) => CalendarEvent(
      id: id,
      householdId: family.householdId,
      calendarResourceId: family.calendarResourceId,
      title: 'Original',
      localStart: DateTime(2026, 10, 15, 17),
      timezone: 'Etc/UTC',
      durationMinutes: 60,
      childIds: [],
      revision: 1,
      updatedAt: DateTime.utc(2026),
    );
    final first = event(newId()), other = event(newId());
    for (final e in [first, other]) {
      repo.saveEvent(e);
      repo.applyRemote(
        operationId: newId(),
        event: e.copyWith(title: 'Concurrent'),
        vector: {b: 1},
      );
    }
    final stale = repo
        .openConflicts()
        .firstWhere((c) => c.local.id == first.id)
        .id;
    repo.applyRemote(
      operationId: newId(),
      event: first.copyWith(title: 'Resolved'),
      vector: {a: 2, b: 1},
    );
    expect(
      repo.applyRemote(
        operationId: newId(),
        event: first.copyWith(title: 'Old snapshot'),
        vector: {b: 1},
      ),
      RemoteApplyResult.stale,
    );
    expect(repo.openConflicts(), hasLength(1));
    expect(repo.openConflicts().single.local.id, other.id);
    expect(
      () => repo.resolveConflict(stale, useRemote: true),
      throwsStateError,
    );
    expect(
      repo.load()!.events.firstWhere((e) => e.id == first.id).title,
      'Resolved',
    );
  });
}
