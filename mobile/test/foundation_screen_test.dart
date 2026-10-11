import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/app/sarti_app.dart';
import 'package:sarti_mobile/src/core/database/sqlcipher_verifier.dart';
import 'package:sarti_mobile/src/features/foundation/foundation_providers.dart';

void main() {
  testWidgets('shows the product promise and secure-storage readiness', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localEncryptionStatusProvider.overrideWith(
            (ref) async => const LocalEncryptionStatus(engineVersion: 'test'),
          ),
        ],
        child: const SartiApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("Your family's wise companion."), findsOneWidget);
    expect(find.text('Local encryption engine ready'), findsOneWidget);
  });
}
