import 'package:integration_test/integration_test.dart';

import '../test/multi_household_state_test.dart' as contexts;
import '../test/recovery_phrase_confirmation_test.dart' as recovery;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  contexts.main();
  recovery.main();
}
