import 'package:integration_test/integration_test.dart';

import '../test/support/retention_scenarios.dart';
import '../test/retention_migration_crypto_test.dart' as migration_crypto;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  retentionScenarios();
  migration_crypto.main();
}
