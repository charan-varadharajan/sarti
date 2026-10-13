import 'dart:convert';

import 'package:sarti_mobile/src/core/ids.dart';
import 'package:sarti_mobile/src/features/ai/event_parser.dart';

class ProtectedPrompt {
  ProtectedPrompt._(List<String> tokens, this._replacements)
    : tokens = List.unmodifiable(tokens);

  final List<String> tokens;
  final Map<String, String> _replacements;

  String get text => jsonEncode({'version': 1, 'tokens': tokens});

  // Exact labels only: never substitute inside unrelated model text.
  Map<String, dynamic> restoreJson(Map<String, dynamic> value) {
    dynamic restore(dynamic item) {
      if (item is String) return _replacements[item] ?? item;
      if (item is List) return item.map(restore).toList();
      if (item is Map) {
        return item.map(
          (key, value) => MapEntry(key.toString(), restore(value)),
        );
      }
      return item;
    }

    return restore(value) as Map<String, dynamic>;
  }

  /// Schema validation plus evidence checks; cloud output cannot invent timing.
  Map<String, dynamic>? acceptResponse(Map<String, dynamic> value) {
    const fields = {
      'timeHour',
      'timeMinute',
      'recurrence',
      'recurrenceWeekday',
    };
    if (value.keys.any((key) => !fields.contains(key))) return null;
    final source = tokens.join(' ');
    final parsed = const DeterministicEventParser().parse(source);
    var time = parsed.timeOfDay;
    if (tokens.contains('noon')) time = const ParsedTime(12, 0);
    if (tokens.contains('midnight')) {
      if (tokens.contains('noon')) return null;
      time = const ParsedTime(0, 0);
    }
    // Multiple clock references require local clarification, not a model choice.
    final clocks = RegExp(
      r'\b(?:\d{1,2}(?::\d{2})?\s*(?:am|pm)|\d{1,2}:\d{2}|noon|midnight)\b',
    ).allMatches(source).length;
    if (value.containsKey('timeHour') || value.containsKey('timeMinute')) {
      if (time == null ||
          clocks != 1 ||
          value['timeHour'] is! int ||
          value['timeMinute'] is! int ||
          value['timeHour'] != time.hour ||
          value['timeMinute'] != time.minute) {
        return null;
      }
    }
    if (value.containsKey('recurrence') ||
        value.containsKey('recurrenceWeekday')) {
      if (parsed.recurrenceFrequency == null ||
          value['recurrence'] != parsed.recurrenceFrequency!.name) {
        return null;
      }
      if (value.containsKey('recurrenceWeekday') &&
          (value['recurrenceWeekday'] is! int ||
              value['recurrenceWeekday'] != parsed.recurrenceWeekday)) {
        return null;
      }
    }
    return value;
  }
}

/// Conservative tokenization, not general-purpose anonymization or PII detection.
class PromptPseudonymizer {
  const PromptPseudonymizer();

  static const _words = {
    'has',
    'have',
    'is',
    'a',
    'an',
    'the',
    'for',
    'and',
    'at',
    'in',
    'on',
    'to',
    'remind',
    'pick',
    'up',
    'pickup',
    'drop',
    'off',
    'dropoff',
    'swimming',
    'karate',
    'football',
    'soccer',
    'basketball',
    'tennis',
    'dance',
    'music',
    'piano',
    'practice',
    'lesson',
    'lessons',
    'class',
    'birthday',
    'school',
    'every',
    'day',
    'week',
    'daily',
    'weekly',
    'today',
    'tomorrow',
    'this',
    'next',
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
    'am',
    'pm',
    'noon',
    'midnight',
    'hour',
    'hours',
    'minute',
    'minutes',
  };

  ProtectedPrompt? protect(
    String input, {
    required Map<String, String> childAliases,
    Iterable<String> guardianNames = const [],
    Iterable<String> sensitiveLocations = const [],
  }) {
    if (input.isEmpty || input.length > 1000) return null;
    final entities = <String, String>{};
    final reverse = <String, String>{};
    bool add(String name, String kind) {
      final trimmed = name.trim();
      if (trimmed.isEmpty) return false;
      final key = trimmed.toLowerCase();
      if (entities.containsKey(key)) return false; // Ambiguous local context.
      final token = '$kind-${newId()}';
      entities[key] = token;
      reverse[token] = trimmed;
      return true;
    }

    for (final name in childAliases.keys) {
      if (!add(name, 'child')) return null;
    }
    for (final name in guardianNames) {
      if (!add(name, 'guardian')) return null;
    }
    for (final place in sensitiveLocations.toSet()) {
      if (!add(place, 'place')) return null;
    }
    final names = entities.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    // One pass avoids reinterpreting generated labels as names or locations.
    final matcher = RegExp(
      [
        if (names.isNotEmpty)
          '(?<![\\p{L}\\p{N}_])(?:${names.map(RegExp.escape).join('|')})(?![\\p{L}\\p{N}_])',
        r'\d+(?::\d+)?',
        r'[\p{L}\p{N}_]+',
        r'[\s,.]+',
      ].join('|'),
      caseSensitive: false,
      unicode: true,
    );
    final tokens = <String>[];
    var offset = 0;
    while (offset < input.length) {
      final match = matcher.matchAsPrefix(input, offset);
      if (match == null) return null;
      final word = match.group(0)!.toLowerCase();
      offset = match.end;
      if (RegExp(r'^[\s,.]+$').hasMatch(word)) continue;
      final entity = entities[word];
      if (entity != null) {
        tokens.add(entity);
      } else if (_words.contains(word)) {
        tokens.add(word);
      } else if (RegExp(r'^\d{1,2}(:\d{2})?$').hasMatch(word)) {
        final parts = word.split(':').map(int.parse).toList();
        if (parts.first > 23 || (parts.length == 2 && parts.last > 59)) {
          return null;
        }
        tokens.add(word);
      } else {
        return null; // No raw-text escape hatch, even after partial redaction.
      }
      if (tokens.length > 100) return null;
    }
    if (tokens.isEmpty) return null;
    return ProtectedPrompt._(tokens, reverse);
  }
}
