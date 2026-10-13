import 'package:integration_test/integration_test.dart';

import '../test/support/calendar_grid_scenarios.dart';
import '../test/support/calendar_today_scenarios.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  calendarGridScenarios();
  calendarTodayScenarios();
}
