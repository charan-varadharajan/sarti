import 'package:sqlite3/sqlite3.dart';

class LocalEncryptionStatus {
  const LocalEncryptionStatus({required this.engineVersion});

  final String engineVersion;
}

class SqlCipherVerifier {
  const SqlCipherVerifier();

  LocalEncryptionStatus verify() {
    final database = sqlite3.openInMemory();
    try {
      final result = database.select('PRAGMA cipher_version');
      if (result.isEmpty || result.first.values.isEmpty) {
        throw StateError('SQLCipher is unavailable.');
      }
      final version = result.first.values.first;
      if (version is! String || version.trim().isEmpty) {
        throw StateError('SQLCipher returned an invalid version.');
      }
      return LocalEncryptionStatus(engineVersion: version);
    } finally {
      database.close();
    }
  }
}
