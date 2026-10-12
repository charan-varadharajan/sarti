import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/core/ids.dart';
import 'package:sarti_mobile/src/features/ai/native_ai_provider.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_controller.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_screen.dart';
import 'package:timezone/data/latest.dart' as tz_data;

void main() {
  setUpAll(tz_data.initializeTimeZones);

  testWidgets('natural-language event requires review and supports undo', (
    tester,
  ) async {
    final database = SartiDatabase.open(':memory:', Uint8List(32));
    addTearDown(database.close);
    final repository = CalendarRepository(database, deviceId: newId());
    repository.createFamily(name: 'Family', ownerName: 'Parent');
    repository.addChild('Mia', 0xFF8E6CEF);
    final controller = CalendarController(
      repository,
      timezone: 'America/Vancouver',
    );
    final provider = NativeEventAiProvider(_UnavailableBridge());

    await tester.pumpWidget(
      MaterialApp(
        home: CalendarScreen(controller: controller, nativeAi: provider),
      ),
    );
    await tester.tap(find.byTooltip('Add with natural language'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Event description'),
      'Mia has swimming tomorrow at 5pm',
    );
    await tester.pump();
    final previewButton = find.widgetWithText(FilledButton, 'Preview');
    expect(tester.widget<FilledButton>(previewButton).onPressed, isNotNull);
    await tester.tap(previewButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Review suggestion'), findsOneWidget);
    expect(
      find.text('Nothing is saved until you approve this suggestion.'),
      findsOneWidget,
    );
    expect(repository.load()!.events, isEmpty);

    await tester.tap(find.text('Add to calendar'));
    await tester.pumpAndSettle();
    expect(repository.load()!.events.single.title, 'swimming');
    expect(repository.load()!.events.single.childIds, hasLength(1));

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(repository.load()!.events, isEmpty);
  });
}

class _UnavailableBridge implements NativeAiBridge {
  @override
  Future<NativeAiAvailability> availability() async =>
      NativeAiAvailability.unsupported;

  @override
  Future<String> generate(String prompt) =>
      throw StateError('Fallback must not call native generation.');
}
