import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/core/crypto/resource_crypto.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/core/ids.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_controller.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_screen.dart';
import 'package:sarti_mobile/src/features/sync/sync_engine.dart';
import 'package:sodium/sodium.dart';
import 'package:timezone/data/latest.dart' as zones;

import 'multi_household_state_test.dart' show OrderedRelay;

class _ReviewRelay extends OrderedRelay implements SequenceReviewRelay {
  _ReviewRelay(this.outcome);
  final String outcome;
  bool unavailable = false, wrongDevice = false;
  @override
  Future<void> upload(RelayEnvelope envelope) async {
    if (unavailable) throw StateError('Lost write authority');
    if (outcome == 'not_accepted' && accepted.isEmpty && loseReply) {
      loseReply = false;
      throw StateError('Interrupted before acceptance');
    }
    return super.upload(envelope);
  }

  @override
  Future<SequenceReceipt> reviewSequence(RelayEnvelope original) async {
    if (!unavailable) throw StateError('Retry remains authorized');
    return SequenceReceipt(
      operationId: original.operationId,
      deviceId: wrongDevice ? newId() : original.authorDeviceId,
      lastDeviceSequence: accepted.length,
      receipt: outcome,
    );
  }
}

void main() {
  setUpAll(zones.initializeTimeZones);
  for (final outcome in ['accepted', 'not_accepted', 'unknown']) {
    test(
      'S5-OFFLINE-004 $outcome receipt preserves original intent and resumes independent uploads',
      () async {
        final sodium = await SodiumInit.init();
        final db = SartiDatabase.open(':memory:', Uint8List(32));
        addTearDown(db.close);
        final device = newId();
        final repo = CalendarRepository(db, deviceId: device);
        final a = repo.createFamily(name: 'A');
        final c = CalendarController(repo, timezone: 'Etc/UTC');
        addTearDown(c.dispose);
        c.save(
          title: 'Unsent A canary',
          localStart: DateTime(2026, 12, 1, 12),
          durationMinutes: 60,
          childIds: [],
        );
        final b = repo.createFamily(name: 'B');
        for (final f in [a, b]) {
          db.setResourceKey(
            f.calendarResourceId,
            1,
            sodium.randombytes.buf(32),
          );
        }
        final relay = _ReviewRelay(outcome)..loseReply = true;
        final engine = SyncEngine(
          database: db,
          repository: repo,
          crypto: ResourceCrypto(sodium),
          sodium: sodium,
          relay: relay,
          deviceId: device,
        );
        await expectLater(engine.synchronize(a.householdId), throwsStateError);
        final original = db.raw
            .select(
              'SELECT * FROM outbox WHERE family_id=? ORDER BY operation_id',
              [a.householdId],
            )
            .map((r) => Map<String, Object?>.from(r))
            .toList();
        final bytes = original.singleWhere(
          (r) => r['envelope_json'] != null,
        )['envelope_json'];
        var fingerprint = engine.pendingFingerprint(a.householdId);
        await expectLater(
          engine.quarantineUnavailableFamily(
            a.householdId,
            reviewedFingerprint: fingerprint,
          ),
          throwsStateError,
        );
        relay.unavailable = true;
        relay.wrongDevice = true;
        await expectLater(
          engine.quarantineUnavailableFamily(
            a.householdId,
            reviewedFingerprint: fingerprint,
          ),
          throwsStateError,
        );
        expect(engine.pendingFingerprint(a.householdId), fingerprint);
        expect(db.raw.select('SELECT * FROM recovery_intents'), isEmpty);
        relay.wrongDevice = false;
        // A fresh local change during review invalidates that review.
        repo
            .forHousehold(a.householdId)
            .addChild('Synthetic child', 0xffabcdef);
        await expectLater(
          engine.quarantineUnavailableFamily(
            a.householdId,
            reviewedFingerprint: fingerprint,
          ),
          throwsStateError,
        );
        fingerprint = engine.pendingFingerprint(a.householdId);
        expect(
          await engine.quarantineUnavailableFamily(
            a.householdId,
            reviewedFingerprint: fingerprint,
          ),
          3,
        );
        final saved = db.raw.select(
          'SELECT * FROM recovery_intents WHERE family_id=?',
          [a.householdId],
        );
        expect(saved, hasLength(3));
        expect(saved.every((r) => r['status'] == 'quarantined'), isTrue);
        final exact = saved.singleWhere(
          (r) => r['original_envelope_json'] != null,
        );
        expect(exact['original_envelope_json'], bytes);
        expect(exact['server_receipt'], outcome);
        for (final old in original) {
          final kept = saved.singleWhere(
            (r) => r['source_operation_id'] == old['operation_id'],
          );
          expect(kept['payload_json'], old['payload_json']);
          expect(kept['vector_json'], old['vector_json']);
        }
        expect(
          db.raw.select('SELECT * FROM outbox WHERE family_id=?', [
            a.householdId,
          ]),
          isEmpty,
        );
        expect(repo.load()!.householdId, b.householdId);
        relay.unavailable = false;
        final report = await engine.synchronize(b.householdId);
        expect(report.uploaded, 1);
        expect(relay.accepted.last.familyId, b.householdId);
        expect(
          relay.accepted.last.deviceSequence,
          outcome == 'not_accepted' ? 1 : 2,
        );
        expect(
          db.raw.select('SELECT title FROM events').single['title'],
          'Unsent A canary',
        );
        final scoped = repo.forHousehold(a.householdId);
        scoped.cacheRetentionPolicy({
          'period': 'week',
          'enabled': true,
          'revision': 1,
          'can_manage': true,
        });
        final eventId = scoped.load()!.events.single.id;
        expect(
          scoped.sweepRetention(DateTime.utc(2027, 1, 1), canAdminister: true),
          [eventId],
        );
        expect(scoped.load()!.events, isEmpty);
        expect(
          db.raw
              .select(
                'SELECT original_envelope_json FROM recovery_intents WHERE original_envelope_json IS NOT NULL',
              )
              .single['original_envelope_json'],
          bytes,
        );
        expect(
          db.raw
              .select(
                "SELECT payload_json FROM recovery_intents WHERE kind='event_upserted'",
              )
              .single['payload_json'],
          original.singleWhere(
            (r) => r['kind'] == 'event_upserted',
          )['payload_json'],
        );
        expect(db.raw.select('PRAGMA foreign_key_check'), isEmpty);
      },
    );
  }

  testWidgets(
    'S5-OFFLINE-005 shipping recovery card requires explicit review, cancellation preserves pending bytes',
    (tester) async {
      final db = SartiDatabase.open(':memory:', Uint8List(32));
      final repo = CalendarRepository(db, deviceId: newId());
      final family = repo.createFamily();
      db.raw.execute("UPDATE outbox SET envelope_json='synthetic exact bytes'");
      final c = CalendarController(repo, timezone: 'Etc/UTC');
      addTearDown(() {
        c.dispose();
        db.close();
      });
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: CalendarScreen(
            controller: c,
            onReviewPending: (id, fingerprint) async {
              calls++;
              expect(id, family.householdId);
              expect(fingerprint, pendingOperationFingerprint(db, id));
              return 1;
            },
          ),
        ),
      );
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Households'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('review-pending-${family.householdId}')));
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(
        db.raw
            .select('SELECT envelope_json FROM outbox')
            .single['envelope_json'],
        'synthetic exact bytes',
      );
      await tester.tap(find.byKey(Key('review-pending-${family.householdId}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Preserve and resume other households'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
