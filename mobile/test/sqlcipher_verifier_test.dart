import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/core/database/sqlcipher_verifier.dart';

void main() {
  test('loads a real SQLCipher engine', () {
    final status = const SqlCipherVerifier().verify();

    expect(status.engineVersion, isNotEmpty);
  });
}
