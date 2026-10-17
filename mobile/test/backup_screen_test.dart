import 'support/recovery_confirmation_helper.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/features/backup/backup_screen.dart';

void main() {
  const phrase =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
  testWidgets(
    'BACKUP-MOB-003 upload requires saving phrase and explicit confirmation',
    (tester) async {
      var uploaded = false;
      await tester.pumpWidget(
        MaterialApp(
          home: BackupScreen(
            hasBackup: false,
            canCreate: true,
            generatePhrase: () => phrase,
            create: (_) async {
              uploaded = true;
            },
            restore: (_) async {},
            remove: () async {},
          ),
        ),
      );
      await tester.tap(find.text('Generate recovery phrase'));
      await tester.pump();
      expect(uploaded, isFalse);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Encrypt and upload backup'),
            )
            .onPressed,
        isNull,
      );
      await confirmFixturePhrase(tester, phrase);
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.ensureVisible(find.text('Encrypt and upload backup'));
      await tester.tap(find.text('Encrypt and upload backup'));
      await tester.pumpAndSettle();
      expect(uploaded, isTrue);
      expect(find.text('Encrypted backup uploaded.'), findsOneWidget);
      expect(find.text(phrase), findsNothing);
    },
  );
  testWidgets(
    'BACKUP-MOB-004 restore validates phrase and requires explicit action',
    (tester) async {
      var restored = false;
      await tester.pumpWidget(
        MaterialApp(
          home: BackupScreen(
            hasBackup: true,
            canCreate: false,
            generatePhrase: () => phrase,
            create: (_) async {},
            restore: (_) async {
              restored = true;
            },
            remove: () async {},
          ),
        ),
      );
      expect(restored, isFalse);
      await tester.enterText(find.byType(TextField), 'bad phrase');
      await tester.tap(find.text('Restore backup'));
      await tester.pumpAndSettle();
      expect(restored, isFalse);
      await tester.enterText(find.byType(TextField), phrase);
      await tester.tap(find.text('Restore backup'));
      await tester.pumpAndSettle();
      expect(restored, isTrue);
      expect(find.text('Backup restored securely.'), findsOneWidget);
    },
  );
}
