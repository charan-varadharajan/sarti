import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/features/backup/backup_restore_card.dart';

void main() {
  testWidgets('stores recovered key only after successful restore', (
    tester,
  ) async {
    Uint8List? stored;
    await tester.pumpWidget(
      MaterialApp(
        home: BackupRestoreCard(
          restore: (phrase) async {
            expect(phrase, 'one two');
            return Uint8List(32);
          },
          storeDatabaseKey: (key) async => stored = key,
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'one two');
    await tester.tap(find.text('Restore backup'));
    await tester.pumpAndSettle();
    expect(stored, Uint8List(32));
    expect(find.text('Backup restored securely.'), findsOneWidget);
  });

  testWidgets('does not store a key when restore fails', (tester) async {
    var stored = false;
    await tester.pumpWidget(
      MaterialApp(
        home: BackupRestoreCard(
          restore: (_) async => throw StateError('bad'),
          storeDatabaseKey: (_) async => stored = true,
        ),
      ),
    );
    await tester.tap(find.text('Restore backup'));
    await tester.pumpAndSettle();
    expect(stored, isFalse);
    expect(find.textContaining('Could not restore'), findsOneWidget);
  });
}
