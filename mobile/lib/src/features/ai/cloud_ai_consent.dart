import 'package:flutter/foundation.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/features/ai/gemini_ai_provider.dart';

typedef GeminiProviderFactory = GeminiAiProvider Function(String apiKey);

class CloudAiConsentStore {
  const CloudAiConsentStore(this.database);

  static const disclosureVersion = 1;
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

/// Creates the Gemini adapter only after consent and only when a key exists.
/// Calling code must request a provider at the point of use; constructing this
/// gate never initializes the provider.
class CloudAiGate {
  CloudAiGate({
    required this.consent,
    required this.apiKey,
    GeminiProviderFactory? providerFactory,
  }) : _providerFactory = providerFactory ?? GeminiAiProvider.new;

  final CloudAiConsentController consent;
  final String apiKey;
  final GeminiProviderFactory _providerFactory;

  bool get available => apiKey.trim().isNotEmpty;

  GeminiAiProvider? createProvider() {
    if (!consent.enabled || !available) return null;
    return _providerFactory(apiKey);
  }
}
