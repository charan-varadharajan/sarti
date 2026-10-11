import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarti_mobile/src/core/database/sqlcipher_verifier.dart';

final sqlCipherVerifierProvider = Provider<SqlCipherVerifier>(
  (ref) => const SqlCipherVerifier(),
);

final localEncryptionStatusProvider = FutureProvider<LocalEncryptionStatus>((
  ref,
) async {
  return ref.watch(sqlCipherVerifierProvider).verify();
});
