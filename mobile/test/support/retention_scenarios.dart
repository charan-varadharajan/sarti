import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/core/ids.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/features/calendar/domain/calendar_event.dart';
import 'package:sarti_mobile/src/features/calendar/domain/calendar_retention.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_controller.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_retention_screen.dart';
import 'package:timezone/data/latest.dart' as zones;

import 'sarti_test_harness.dart';

void retentionScenarios() {
  final now = DateTime.utc(2026, 10, 13, 18);
  late SartiDatabase db;
  late CalendarRepository repo;
  late String family, resource, device;
  CalendarEvent event({
    DateTime? start,
    RecurrenceRule? recurrence,
    String? calendar,
    int duration = 60,
  }) => CalendarEvent(
    id: newId(),
    householdId: family,
    calendarResourceId: calendar ?? resource,
    title: 'Synthetic appointment',
    notes: 'Sensitive fixture',
    localStart: start ?? DateTime.utc(2026, 9, 1, 12),
    timezone: 'Etc/UTC',
    durationMinutes: duration,
    childIds: [],
    reminderMinutes: [30],
    revision: 1,
    updatedAt: now,
    recurrence: recurrence,
  );
  void acknowledged() => db.raw.execute("UPDATE outbox SET state='uploaded'");
  void policy({String period = 'week', bool admin = true}) =>
      repo.cacheRetentionPolicy({
        'period': period,
        'revision': 0,
        'enabled': true,
        'can_manage': admin,
      });
  setUp(() {
    zones.initializeTimeZones();
    db = SartiDatabase.open(':memory:', Uint8List(32));
    device = newId();
    repo = CalendarRepository(db, deviceId: device, adultId: newId());
    final f = repo.createFamily();
    family = f.householdId;
    resource = f.calendarResourceId;
  });
  tearDown(() => db.close());

  test('RETENTION-TIME-001 end boundary, months, Never and future', () {
    expect(
      CalendarRetention.month.cutoff(DateTime.utc(2024, 3, 31, 12), 'Etc/UTC'),
      DateTime.utc(2024, 2, 29, 12),
    );
    expect(
      CalendarRetention.year.cutoff(DateTime.utc(2024, 2, 29, 12), 'Etc/UTC'),
      DateTime.utc(2023, 2, 28, 12),
    );
    final boundary = event(
      start: now.subtract(const Duration(days: 7, hours: 1)),
    );
    expect(
      calendarHistoryExpired(boundary, CalendarRetention.week, now),
      isTrue,
    );
    expect(
      calendarHistoryExpired(
        boundary,
        CalendarRetention.week,
        now.subtract(const Duration(microseconds: 1)),
      ),
      isFalse,
    );
    expect(
      calendarHistoryExpired(event(start: now), CalendarRetention.week, now),
      isFalse,
    );
    expect(
      calendarHistoryExpired(boundary, CalendarRetention.never, now),
      isFalse,
    );
    final dst = event(start: DateTime.utc(2026, 3, 8, 1, 30), duration: 120);
    final local = CalendarEvent.fromJson({
      ...dst.toJson(),
      'timezone': 'America/Vancouver',
      'localStart': '2026-03-08T01:30:00-08:00',
    });
    expect(completedCalendarEnd(local), DateTime.utc(2026, 3, 8, 11, 30));
  });
  test('RETENTION-SERIES-001 active, finite and evaluator cap', () {
    expect(
      completedCalendarEnd(
        event(
          recurrence: const RecurrenceRule(
            frequency: RecurrenceFrequency.weekly,
          ),
        ),
      ),
      isNull,
    );
    expect(
      calendarHistoryExpired(
        event(
          recurrence: const RecurrenceRule(
            frequency: RecurrenceFrequency.weekly,
            count: 2,
          ),
        ),
        CalendarRetention.week,
        now,
      ),
      isTrue,
    );
    expect(
      completedCalendarEnd(
        event(
          recurrence: const RecurrenceRule(
            frequency: RecurrenceFrequency.daily,
            count: 10001,
          ),
        ),
      ),
      isNull,
    );
    expect(
      calendarHistoryExpired(
        event(
          start: DateTime.utc(2026, 10, 1),
          recurrence: RecurrenceRule(
            frequency: RecurrenceFrequency.daily,
            untilLocalDate: DateTime(2026, 12, 1),
          ),
        ),
        CalendarRetention.week,
        now,
      ),
      isFalse,
    );
  });
  test(
    'RETENTION-SYNC-001 purge actual content, minimal retry, stale replay',
    () {
      final old = event();
      repo.saveEvent(old);
      acknowledged();
      policy();
      final original = Map<String, int>.from(
        jsonDecode(
          db.raw
                  .select('SELECT vector_json FROM event_versions')
                  .single['vector_json']
              as String,
        ) as Map,
      );
      expect(repo.sweepRetention(now, canAdminister: true), [old.id]);
      expect(repo.load()!.events, isEmpty);
      final payload = jsonDecode(
        db.raw
                .select(
                  "SELECT payload_json FROM outbox WHERE kind='retention_deleted'",
                )
                .single['payload_json']
            as String,
      ) as Map;
      expect(payload.keys.toSet(), {
        'id',
        'householdId',
        'resourceId',
        'vector',
        'deletedAt',
      });
      expect(jsonEncode(payload), isNot(contains('Sensitive fixture')));
      expect(db.raw.select('SELECT * FROM reminders'), isEmpty);
      expect(db.raw.select('SELECT * FROM event_versions'), isEmpty);
      expect(repo.sweepRetention(now, canAdminister: true), isEmpty);
      expect(
        repo.applyRemote(operationId: newId(), event: old, vector: original),
        RemoteApplyResult.stale,
      );
      expect(() => repo.saveEvent(old), throwsStateError);
    },
  );
  test(
    'RETENTION-SEC-001 non-admin cannot clean shared but own private expires',
    () {
      final shared = event();
      repo.saveEvent(shared);
      final private = event(calendar: repo.ensurePersonalCalendar());
      repo.saveAdultAppointment(private, share: false);
      acknowledged();
      policy(admin: false);
      expect(repo.sweepRetention(now, canAdminister: false), [private.id]);
      expect(repo.load()!.events.map((e) => e.id), [shared.id]);
      expect(
        () => repo.applyRetentionDeletion(
          operationId: newId(),
          familyId: newId(),
          resourceId: resource,
          vector: {device: 2},
          payload: {'id': shared.id},
        ),
        throwsFormatException,
      );
      expect(repo.load()!.events.single.id, shared.id);
    },
  );
  test('RETENTION-CONFLICT-001 pending edits and genuine concurrent deletion preserved', () {
    final old = event();
    repo.saveEvent(old);
    policy();
    expect(repo.sweepRetention(now, canAdminister: true), isEmpty);
    acknowledged();
    final other = newId();
    final payload = <String, Object?>{
      'id': old.id,
      'householdId': family,
      'resourceId': resource,
      'vector': {other: 1},
      'deletedAt': now.toIso8601String(),
    };
    expect(
      repo.applyRetentionDeletion(
        operationId: newId(),
        familyId: family,
        resourceId: resource,
        vector: {other: 1},
        payload: payload,
      ),
      RemoteApplyResult.conflict,
    );
    expect(repo.load()!.events.single.title, old.title);
    expect(repo.retentionConflicts(), hasLength(1));
    repo.resolveRetentionConflict(old.id, keep: true);
    acknowledged();
    expect(repo.sweepRetention(now, canAdminister: true), isEmpty);
    expect(repo.load()!.events.single.title, old.title);
    repo.queueGuardianHandoff(
      invitationId: newId(),
      profileResourceId: newId(),
      childResourceIds: {},
      guardianId: newId(),
      guardianName: 'Prepared guardian',
    );
    expect(
      db.raw.select(
        "SELECT * FROM outbox WHERE state='pending' AND kind='retention_kept'",
      ),
      hasLength(1),
    );
  });
  test('RETENTION-SYNC-002 remote minimal deletion, duplicate, concurrent edit review', () {
    final old = event();
    repo.saveEvent(old);
    acknowledged();
    final op = newId();
    final vector = {device: 2};
    final payload = <String, Object?>{
      'id': old.id,
      'householdId': family,
      'resourceId': resource,
      'vector': vector,
      'deletedAt': now.toIso8601String(),
    };
    expect(
      repo.applyRetentionDeletion(
        operationId: op,
        familyId: family,
        resourceId: resource,
        vector: vector,
        payload: payload,
      ),
      RemoteApplyResult.applied,
    );
    expect(
      repo.applyRetentionDeletion(
        operationId: op,
        familyId: family,
        resourceId: resource,
        vector: vector,
        payload: payload,
      ),
      RemoteApplyResult.duplicate,
    );
    expect(
      repo.applyRemote(
        operationId: newId(),
        event: old,
        vector: {device: 1, newId(): 1},
      ),
      RemoteApplyResult.conflict,
    );
    expect(repo.load()!.events, isEmpty);
    expect(repo.retentionConflicts(), hasLength(1));
    repo.resolveRetentionConflict(old.id, keep: false);
    expect(repo.retentionConflicts(), isEmpty);
    expect(repo.load()!.events, isEmpty);
  });
  test('RETENTION-RESTORE-001 restored family pauses destructive sweep', () {
    repo.saveEvent(event());
    acknowledged();
    policy();
    db.raw.execute(
      "INSERT INTO app_preferences VALUES ('retention-recovery-pending','true')",
    );
    final controller = CalendarController(
      repo,
      timezone: 'Etc/UTC',
      clock: () => now,
    );
    expect(controller.applyRetention(canAdminister: true), isEmpty);
    expect(repo.load()!.events, hasLength(1));
    controller.dispose();
  });
  test(
    'RETENTION-REMOVED-001 expired manual tombstones also lose event details',
    () {
      final old = event().copyWith(deleted: true);
      repo.saveEvent(old);
      acknowledged();
      policy();
      expect(repo.load()!.events, isEmpty);
      expect(db.raw.select('SELECT title FROM events'), hasLength(1));
      expect(repo.sweepRetention(now, canAdminister: true), [old.id]);
      expect(db.raw.select('SELECT title FROM events'), isEmpty);
      expect(db.raw.select('SELECT * FROM calendar_deletions'), hasLength(1));
    },
  );
  testWidgets(
    'RETENTION-MOB-001 prepared screen applies default, removes old not future, cancels reminder',
    (tester) async {
      final old = event();
      final future = event(start: now.add(const Duration(days: 1)));
      repo.saveEvent(old);
      repo.saveEvent(future);
      acknowledged();
      policy();
      final reminders = TestReminderScheduler();
      final controller = CalendarController(
        repo,
        timezone: 'Etc/UTC',
        clock: () => now,
        reminders: reminders,
      );
      controller.updateRetention = (period, revision) async {
        policy(period: period.name);
        controller.applyRetention(canAdminister: true);
      };
      await tester.pumpWidget(
        MaterialApp(home: CalendarRetentionScreen(controller: controller)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review and apply'));
      await tester.pumpAndSettle();
      expect(repo.load()!.events, hasLength(2));
      expect(find.textContaining('1 entries on this phone'), findsOneWidget);
      await tester.tap(find.text('Apply to family'));
      await tester.pumpAndSettle();
      expect(repo.load()!.events.single.id, future.id);
      expect(reminders.cancelledEventIds, [old.id]);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets('RETENTION-UI-001 non-admin view cannot change family policy', (
    tester,
  ) async {
    policy(admin: false);
    final controller = CalendarController(repo, timezone: 'Etc/UTC');
    controller.updateRetention = (_, _) async =>
        fail('Unauthorized policy write');
    await tester.pumpWidget(
      MaterialApp(home: CalendarRetentionScreen(controller: controller)),
    );
    expect(find.text('Review and apply'), findsNothing);
    expect(find.textContaining('Only the family owner'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
