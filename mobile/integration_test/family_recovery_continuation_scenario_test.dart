import 'package:integration_test/integration_test.dart';

import '../test/family_recovery_continuation_test.dart' as recovery;
import '../test/recovery_retention_minimization_test.dart' as retention;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  recovery.familyRecoveryScenarios();
  retention.main();
}
