import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/core/ids.dart';
import 'package:sarti_mobile/src/features/ai/native_ai_provider.dart';
import 'package:sarti_mobile/src/features/ai/natural_language_event_dialog.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/features/calendar/data/reminder_scheduler.dart';
import 'package:sarti_mobile/src/features/calendar/domain/calendar_event.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_controller.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_screen.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/household_selector_screen.dart';
import 'package:sarti_mobile/src/features/guardians/guardian_coordinator.dart';
import 'package:sodium/sodium.dart';
import 'package:timezone/data/latest.dart' as zones;

import 'support/guardian_fixture.dart';

class _Reminders implements ReminderScheduler {
  final cancelled = <String>[];
  final scheduled = <String>[];
  @override
  Future<void> cancelFor(String id) async {
    cancelled.add(id);
  }

  @override
  Future<void> replaceFor(CalendarEvent event) async {
    scheduled.add(event.id);
  }
}

class _DelayedAi implements NativeAiBridge {
  final ready = Completer<NativeAiAvailability>();
  @override
  Future<NativeAiAvailability> availability() => ready.future;
  @override
  Future<String> generate(String prompt) async => '{}';
}

void main() {
  setUpAll(zones.initializeTimeZones);

  test('S5-HOUSEHOLD-007 same guardian identity has separate profiles and pickup references in each context', () {
    final db = SartiDatabase.open(':memory:', Uint8List(32));
    final repo = CalendarRepository(db, deviceId: newId());
    final a = repo.createFamily(name: 'A');
    final b = repo.createFamily(name: 'B');
    final adult = newId();
    addTearDown(db.close);
    for (final (family, name) in [(a, 'Guardian in A'), (b, 'Guardian in B')]) {
      final profile = newId();
      db.raw.execute(
        "INSERT INTO resource_catalog VALUES (?,?,'family_profile',1)",
        [profile, family.householdId],
      );
      repo
          .forHousehold(family.householdId)
          .applySharedHousehold(
            operationId: newId(),
            familyId: family.householdId,
            resourceId: profile,
            vector: {repo.deviceId: 1},
            payload: {
              'householdId': family.householdId,
              'name': family.name,
              'guardians': [
                {'id': adult, 'name': name},
              ],
            },
          );
      final c = CalendarController(
        repo.forHousehold(family.householdId),
        timezone: 'Etc/UTC',
      );
      try {
        c.save(
          title: 'Pickup',
          localStart: DateTime(2026, 12, 1),
          durationMinutes: 60,
          childIds: [],
          pickupGuardianId: adult,
        );
      } finally {
        c.dispose();
      }
    }
    expect(
      repo
          .forHousehold(a.householdId)
          .load()!
          .guardians
          .where((g) => g.id == adult)
          .single
          .name,
      'Guardian in A',
    );
    expect(
      repo
          .forHousehold(b.householdId)
          .load()!
          .guardians
          .where((g) => g.id == adult)
          .single
          .name,
      'Guardian in B',
    );
    final foreignOnly = newId();
    db.raw.execute('INSERT INTO guardians VALUES (?,?,?)', [
      foreignOnly,
      a.householdId,
      'A only',
    ]);
    final c = CalendarController(repo, timezone: 'Etc/UTC');
    addTearDown(c.dispose);
    expect(
      () => c.save(
        title: 'Foreign pickup',
        localStart: DateTime(2026, 12, 1),
        durationMinutes: 60,
        childIds: [],
        pickupGuardianId: foreignOnly,
      ),
      throwsA(anything),
    );
    db.raw.execute('DELETE FROM households WHERE id=?', [a.householdId]);
    expect(
      repo.load()!.guardians.where((g) => g.id == adult).single.name,
      'Guardian in B',
    );
    expect(repo.load()!.events.single.pickupGuardianId, adult);
    expect(db.raw.select('PRAGMA foreign_key_check'), isEmpty);
  });

  testWidgets(
    'S5-HOUSEHOLD-002 prepared selector keeps events, colors, reminders and pending work scoped',
    (tester) async {
      final db = SartiDatabase.open(':memory:', Uint8List(32));
      final repo = CalendarRepository(db, deviceId: newId(), adultId: newId());
      final reminders = _Reminders();
      final c = CalendarController(
        repo,
        timezone: 'Etc/UTC',
        reminders: reminders,
      );
      addTearDown(() {
        c.dispose();
        db.close();
      });
      c.createFamily('Household A', 'Me');
      final a = c.family!;
      c.addChild('Synthetic child', 0xffabcdef);
      final eventA = c.save(
        title: 'A canary',
        localStart: DateTime(2026, 12, 1, 9),
        durationMinutes: 60,
        childIds: [],
      );
      c.createFamily('Household B', 'Me');
      final b = c.family!;
      c.addChild('Synthetic child', 0xfffedcba);
      c.save(
        title: 'B canary',
        localStart: DateTime(2026, 12, 1, 10),
        durationMinutes: 60,
        childIds: [],
      );
      final pending = db.raw
          .select('SELECT operation_id,payload_json FROM outbox')
          .map((r) => jsonEncode(r))
          .toList();
      await tester.pumpWidget(MaterialApp(home: CalendarScreen(controller: c)));
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Households'));
      await tester.pumpAndSettle();
      expect(find.byType(HouseholdSelectorScreen), findsOneWidget);
      await tester.tap(find.byKey(Key('select-household-${a.householdId}')));
      await tester.pumpAndSettle();
      expect(c.family!.events.single.title, 'A canary');
      expect(c.family!.children.single.colorArgb, 0xffabcdef);
      expect(reminders.cancelled, isNot(contains(eventA.id)));
      expect(
        db.raw
            .select('SELECT operation_id,payload_json FROM outbox')
            .map((r) => jsonEncode(r))
            .toList(),
        pending,
      );
      expect(
        CalendarRepository(db, deviceId: repo.deviceId).load()!.householdId,
        a.householdId,
      );
      c.selectHousehold(b.householdId);
      await tester.pumpAndSettle();
      expect(c.family!.events.single.title, 'B canary');
      expect(c.family!.children.single.colorArgb, 0xfffedcba);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'S5-HOUSEHOLD-006 remote removal cancels only that household reminder',
    () async {
      final db = SartiDatabase.open(':memory:', Uint8List(32));
      final repo = CalendarRepository(db, deviceId: newId());
      final c = CalendarController(repo, timezone: 'Etc/UTC');
      addTearDown(() {
        c.dispose();
        db.close();
      });
      c.createFamily('A', 'Me');
      final a = c.family!;
      final eventA = c.save(
        title: 'A',
        localStart: DateTime(2026, 12, 1),
        durationMinutes: 60,
        childIds: [],
      );
      c.createFamily('B', 'Me');
      final eventB = c.save(
        title: 'B',
        localStart: DateTime(2026, 12, 1),
        durationMinutes: 60,
        childIds: [],
      );
      final reminders = _Reminders();
      await reconcileHouseholdReminders(reminders, a.householdId, [eventA], []);
      expect(reminders.cancelled, [eventA.id]);
      expect(reminders.cancelled, isNot(contains(eventB.id)));
      await expectLater(
        reconcileHouseholdReminders(
          reminders,
          a.householdId,
          [eventA],
          [eventB],
        ),
        throwsStateError,
      );
      expect(c.family!.events.single.id, eventB.id);
    },
  );

  testWidgets(
    'S5-HOUSEHOLD-003 create additional household preserves recovery in the existing one',
    (tester) async {
      final db = SartiDatabase.open(':memory:', Uint8List(32));
      final repo = CalendarRepository(db, deviceId: newId());
      final a = repo.createFamily(name: 'Household A');
      db.raw.execute(
        "INSERT INTO recovery_state(family_id,phase) VALUES (?,'paused')",
        [a.householdId],
      );
      final c = CalendarController(repo, timezone: 'Etc/UTC');
      addTearDown(() {
        c.dispose();
        db.close();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => HouseholdSelectorScreen(controller: c),
                ),
              ),
              child: const Text('Choose'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('create-additional-household')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('setup-family-name')),
        'Household B',
      );
      await tester.tap(find.byKey(const Key('setup-continue')));
      await tester.pumpAndSettle();
      expect(c.family!.name, 'Household B');
      expect(repo.recoveryPending, isFalse);
      expect(repo.forHousehold(a.householdId).recoveryPending, isTrue);
      expect(repo.localFamilies(), hasLength(2));
      await tester.tap(find.byKey(const Key('setup-open-calendar')));
      await tester.pumpAndSettle();
      expect(find.text('Choose'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'S5-HOUSEHOLD-004 stale manual editor cannot save into the newly selected household',
    (tester) async {
      final db = SartiDatabase.open(':memory:', Uint8List(32));
      final repo = CalendarRepository(db, deviceId: newId());
      final a = repo.createFamily(name: 'A');
      final b = repo.createFamily(name: 'B');
      repo.selectHousehold(a.householdId);
      final c = CalendarController(repo, timezone: 'Etc/UTC');
      addTearDown(() {
        c.dispose();
        db.close();
      });
      await tester.pumpWidget(MaterialApp(home: CalendarScreen(controller: c)));
      await tester.tap(find.text('Event'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-event-manually')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'Stale A draft',
      );
      c.selectHousehold(b.householdId);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(db.raw.select('SELECT * FROM events'), isEmpty);
      expect(find.textContaining('Could not save.'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'S5-HOUSEHOLD-005 delayed native proposal stays bound to its original household',
    (tester) async {
      final db = SartiDatabase.open(':memory:', Uint8List(32));
      final repo = CalendarRepository(db, deviceId: newId());
      final a = repo.createFamily(name: 'A');
      final b = repo.createFamily(name: 'B');
      repo.selectHousehold(a.householdId);
      final c = CalendarController(repo, timezone: 'Etc/UTC');
      addTearDown(() {
        c.dispose();
        db.close();
      });
      final ai = _DelayedAi();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showNaturalLanguageEventDialog(
                context,
                controller: c,
                provider: NativeEventAiProvider(ai),
                initialInput: 'Swimming tomorrow at noon',
              ),
              child: const Text('Describe'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Describe'));
      await tester.pump();
      await tester.pump();
      c.selectHousehold(b.householdId);
      ai.ready.complete(NativeAiAvailability.unsupported);
      await tester.pumpAndSettle();
      expect(
        find.text('Household changed. Cancel and reopen your description.'),
        findsOneWidget,
      );
      expect(db.raw.select('SELECT * FROM events'), isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('S5-INVITE-002 explicit second-household join preserves first-household keys and outbox', () async {
    final sodium = await SodiumInit.init();
    final g = GuardianFixture(sodium);
    addTearDown(g.close);
    final repo = g.f.b.repository;
    final other = repo.createFamily(name: 'Existing household');
    final key = sodium.randombytes.buf(32);
    g.f.b.database.setResourceKey(other.calendarResourceId, 1, key);
    final pending = g.f.b.database.raw
        .select('SELECT * FROM outbox WHERE family_id=?', [other.householdId])
        .map((r) => jsonEncode(r))
        .toList();
    final joining = GuardianCoordinator(
      database: g.f.b.database,
      repository: repo,
      api: g.guardianApi,
      keys: g.f.b.keys,
      joining: true,
      synchronize: () async {
        await g.f.b.keySync.prepare(g.f.familyId);
        await g.f.b.engine.synchronize(g.f.familyId);
      },
    );
    addTearDown(joining.dispose);
    await g.owner.refresh();
    await g.owner.create();
    await joining.accept(g.token);
    expect(repo.load()!.householdId, other.householdId);
    expect(joining.family!.status, 'pending');
    expect(g.f.b.database.resourceKey(g.f.calendarId, 1), isNull);
    await g.owner.approve(g.review, {
      g.f.calendarId: 'read',
      g.profileId: 'read',
    }, 'Parent');
    await joining.refresh();
    expect(joining.ready, isTrue);
    expect(repo.load()!.householdId, g.f.familyId);
    expect(g.f.b.database.resourceKey(other.calendarResourceId, 1), key);
    expect(
      g.f.b.database.raw
          .select('SELECT * FROM outbox WHERE family_id=?', [other.householdId])
          .map((r) => jsonEncode(r))
          .toList(),
      pending,
    );
    expect(g.f.b.database.raw.select('PRAGMA foreign_key_check'), isEmpty);
    repo.selectHousehold(other.householdId);
    expect(repo.load()!.name, 'Existing household');
  });
}
