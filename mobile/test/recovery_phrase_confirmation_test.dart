import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/features/backup/backup_screen.dart';
import 'package:sarti_mobile/src/features/backup/recovery_phrase_confirmation.dart';

import 'support/recovery_confirmation_helper.dart';

void main() {
  const phrase =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
  testWidgets(
    'S5-RECOVERY-MOB-001 word confirmation rejects mistakes and resets on regeneration',
    (tester) async {
      var saves = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: BackupScreen(
            hasBackup: false,
            canCreate: true,
            generatePhrase: () => phrase,
            create: (_) async {
              saves++;
            },
            restore: (_) async {},
            remove: () async {},
          ),
        ),
      );
      await tester.tap(find.text('Generate recovery phrase'));
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(RecoveryPhraseConfirmation),
        matching: find.byType(TextField),
      );
      expect(fields, findsNWidgets(2));
      await tester.enterText(fields.first, 'wrong');
      await tester.pump();
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      final save = find.widgetWithText(
        FilledButton,
        'Encrypt and upload backup',
      );
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      expect(saves, 0);
      await confirmFixturePhrase(tester, phrase);
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
      await tester.ensureVisible(find.text('Generate recovery phrase'));
      await tester.tap(find.text('Generate recovery phrase'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      for (final element in fields.evaluate()) {
        expect((element.widget as TextField).controller!.text, isEmpty);
      }
      expect(saves, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
