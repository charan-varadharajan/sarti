class ProtectedPrompt {
  const ProtectedPrompt(this.text, this._replacements);

  final String text;
  final Map<String, String> _replacements;

  Map<String, dynamic> restoreJson(Map<String, dynamic> value) =>
      _restore(value) as Map<String, dynamic>;

  dynamic _restore(dynamic value) {
    if (value is String) {
      var restored = value;
      for (final entry in _replacements.entries) {
        restored = restored.replaceAll(
          RegExp(RegExp.escape(entry.key), caseSensitive: false),
          entry.value,
        );
      }
      return restored;
    }
    if (value is List) return value.map(_restore).toList();
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), _restore(item)));
    }
    return value;
  }
}

/// Replaces locally known people and places before text crosses the cloud
/// boundary. It is not anonymization: schedule shape can still be identifying.
class PromptPseudonymizer {
  const PromptPseudonymizer();

  ProtectedPrompt protect(
    String input, {
    required Map<String, String> childAliases,
    Iterable<String> sensitiveLocations = const [],
  }) {
    var protected = input;
    final reverse = <String, String>{};

    final names = childAliases.entries.toList()
      ..sort((left, right) => right.key.length.compareTo(left.key.length));
    for (final entry in names) {
      final name = entry.key.trim();
      final alias = entry.value.trim();
      if (name.isEmpty || alias.isEmpty) continue;
      protected = protected.replaceAll(
        RegExp(
          '(?<![A-Za-z0-9])${RegExp.escape(name)}(?![A-Za-z0-9])',
          caseSensitive: false,
        ),
        alias,
      );
      reverse[alias] = name;
    }

    final locations =
        sensitiveLocations
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort((left, right) => right.length.compareTo(left.length));
    for (var index = 0; index < locations.length; index++) {
      final location = locations[index];
      final token = 'place-${index + 1}';
      protected = protected.replaceAll(
        RegExp(RegExp.escape(location), caseSensitive: false),
        token,
      );
      reverse[token] = location;
    }
    return ProtectedPrompt(protected, reverse);
  }
}
