import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/core/crypto/device_key_store.dart';
import 'package:sarti_mobile/src/features/sync/authenticated_calendar_bootstrap.dart';
import 'package:sodium/sodium.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import 'support/child_sync_fixture.dart';
import 'support/sarti_test_harness.dart';

class _Secrets implements SecretStore {
  final _values = <String, String>{};
  @override
  Future<String?> read(String key) async => _values[key];
  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> deleteAll() async => _values.clear();
}

void main() {
  late Sodium sodium;
  setUpAll(() async {
    sodium = await SodiumInit.init();
    tz_data.initializeTimeZones();
  });

  Future<void> open(WidgetTester tester, ChildSyncFixture f) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthenticatedCalendarBootstrap(
          database: f.a.database,
          keys: f.a.keys,
          sodium: sodium,
          secrets: _Secrets(),
          reminders: TestReminderScheduler(),
          timezone: 'America/Vancouver',
          apiBaseUrl: '',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'BOOT-PERM-001 first family immediately exposes owner event and child controls',
    (tester) async {
      final f = ChildSyncFixture(sodium);
      addTearDown(f.close);
      f.a.database.raw.execute('DELETE FROM outbox');
      f.a.database.raw.execute('DELETE FROM households');
      await open(tester, f);
      expect(find.text('Create family'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      // Family creation itself is the behavior under test; other prerequisites
      // (encrypted storage, device keys, offline bootstrap) are prepared directly.
      await tester.tap(find.text('Create family'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FloatingActionButton, 'Event'),
        findsOneWidget,
      );
      expect(find.byTooltip('Add child'), findsOneWidget);
      await tester.tap(find.widgetWithText(FloatingActionButton, 'Event'));
      await tester.pumpAndSettle();
      expect(find.text('New event'), findsOneWidget);
      expect(f.a.repository.load()!.events, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(f.a.repository.load()!.events, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('BOOT-PERM-002 prepared owner retains creation controls', (
    tester,
  ) async {
    final f = ChildSyncFixture(sodium);
    addTearDown(f.close);
    await open(tester, f);
    expect(find.widgetWithText(FloatingActionButton, 'Event'), findsOneWidget);
    expect(find.byTooltip('Add child'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final role in ['guardian', 'revoked']) {
    testWidgets(
      'BOOT-PERM-003 prepared $role cannot gain owner mutation controls',
      (tester) async {
        final f = ChildSyncFixture(sodium);
        addTearDown(f.close);
        f.a.database.raw.execute(
          'INSERT INTO app_preferences(key,value) VALUES (?,?)',
          [
            'family-access-${f.familyId}',
            jsonEncode({'role': role, 'permission': 'read'}),
          ],
        );
        await open(tester, f);
        expect(find.byType(FloatingActionButton), findsNothing);
        expect(find.byTooltip('Add child'), findsNothing);
        await tester.tap(find.text('Week'));
        await tester.pumpAndSettle();
        expect(find.byType(FloatingActionButton), findsNothing);
        expect(find.byTooltip('Add child'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
