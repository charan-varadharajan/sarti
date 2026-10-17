import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/features/backup/recovery_phrase_confirmation.dart';

/// Synthetic fixture words only; never captures a real user's recovery material.
Future<void> confirmFixturePhrase(WidgetTester tester, String phrase) async {
  final fields = find.descendant(
    of: find.byType(RecoveryPhraseConfirmation),
    matching: find.byType(TextField),
  );
  for (final field in fields.evaluate().toList()) {
    final key = (field.widget.key! as ValueKey<String>).value;
    final index = int.parse(key.split('-').last);
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.enterText(finder, phrase.split(' ')[index]);
    await tester.pump();
  }
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}
