import 'package:flutter/foundation.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/features/ai/gemini_ai_provider.dart';

typedef GeminiProviderFactory = GeminiAiProvider Function();

class CloudAiConsentStore {
  const CloudAiConsentStore(this.database);

  static const disclosureVersion = 3;
  static const _key = 'cloud_ai_consent_v$disclosureVersion';

  final SartiDatabase database;

  bool get enabled {
    final rows = database.raw.select(
      'SELECT value FROM app_preferences WHERE key = ?',
      [_key],
    );
    return rows.isNotEmpty && rows.single['value'] == 'enabled';
  }

  void setEnabled(bool value) {
    database.raw.execute(
      '''INSERT INTO app_preferences(key, value) VALUES (?, ?)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value''',
      [_key, value ? 'enabled' : 'disabled'],
    );
  }
}

/// Owns the explicit, reversible consent gate for optional cloud inference.
class CloudAiConsentController extends ChangeNotifier {
  CloudAiConsentController(this.store) : _enabled = store.enabled;

  final CloudAiConsentStore store;
  bool _enabled;

  bool get enabled => _enabled;

  void setEnabled(bool value) {
    if (_enabled == value) return;
    store.setEnabled(value);
    _enabled = value;
    notifyListeners();
  }
}

/// Point-of-use broker gate; never accepts or stores provider credentials.
class CloudAiGate {
  CloudAiGate({
    required this.consent,
    required this.available,
    required this.providerFactory,
  });
  final CloudAiConsentController consent;
  final bool available;
  final GeminiProviderFactory providerFactory;
  GeminiAiProvider? createProvider() =>
      consent.enabled && available ? providerFactory() : null;
}
