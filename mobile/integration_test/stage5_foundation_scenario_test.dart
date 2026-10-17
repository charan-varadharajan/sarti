import 'package:integration_test/integration_test.dart';

import '../test/multi_household_state_test.dart' as contexts;
import '../test/household_switching_test.dart' as switching;
import '../test/sequence_reconciliation_test.dart' as reconciliation;
import '../test/authenticated_sync_runtime_test.dart' as runtime;
import '../test/guardian_scope_migration_test.dart' as guardian_migration;
import '../test/scoped_household_import_test.dart' as scoped_import;
import '../test/email_suggestion_inbox_test.dart' as email;
import '../test/recovery_phrase_confirmation_test.dart' as recovery;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  contexts.main();
  switching.main();
  reconciliation.main();
  runtime.main();
  guardian_migration.main();
  scoped_import.main();
  email.main();
  recovery.main();
}
