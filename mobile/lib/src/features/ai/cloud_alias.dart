import 'dart:math';

/// A non-secret pseudonym used only to remove a child's display name from
/// optional cloud-AI prompts. The alias-to-child mapping remains in SQLCipher.
abstract final class CloudAlias {
  static final Random _random = Random.secure();

  static const _adjectives = [
    'bright',
    'calm',
    'clever',
    'gentle',
    'happy',
    'jolly',
    'kind',
    'lucky',
    'merry',
    'quick',
    'quiet',
    'sunny',
  ];

  static const _animals = [
    'badger',
    'dolphin',
    'falcon',
    'frog',
    'gecko',
    'koala',
    'otter',
    'panda',
    'rabbit',
    'raven',
    'turtle',
    'wombat',
  ];

  static String generate({required String childName}) {
    while (true) {
      final adjective = _adjectives[_random.nextInt(_adjectives.length)];
      final animal = _animals[_random.nextInt(_animals.length)];
      final suffix = 1000 + _random.nextInt(9000);
      final candidate = '$adjective-$animal-$suffix';
      try {
        return validate(candidate, childName: childName);
      } on ArgumentError {
        // Try another combination when a word happens to match the child name.
      }
    }
  }

  static String validate(String value, {required String childName}) {
    final alias = value.trim().toLowerCase();
    if (!RegExp(r'^[a-z][a-z0-9-]{2,31}$').hasMatch(alias)) {
      throw ArgumentError.value(
        value,
        'cloudAlias',
        'Use 3-32 lowercase letters, numbers, or hyphens.',
      );
    }
    final nameParts = childName
        .trim()
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((part) => part.length >= 2)
        .toSet();
    final comparableAlias = alias.replaceAll('-', '');
    final aliasParts = alias.split('-').toSet();
    if (nameParts.contains(comparableAlias) ||
        nameParts.any(aliasParts.contains)) {
      throw ArgumentError.value(
        value,
        'cloudAlias',
        'The private AI alias must differ from the child name.',
      );
    }
    return alias;
  }
}
