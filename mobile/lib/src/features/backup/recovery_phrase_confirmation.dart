import 'dart:math';

import 'package:flutter/material.dart';

/// Transient confirmation only. Never persists answers or includes words in keys.
class RecoveryPhraseConfirmation extends StatefulWidget {
  const RecoveryPhraseConfirmation({
    super.key,
    required this.phrase,
    required this.onChanged,
  });
  final String phrase;
  final ValueChanged<bool> onChanged;

  @override
  State<RecoveryPhraseConfirmation> createState() =>
      _RecoveryPhraseConfirmationState();
}

class _RecoveryPhraseConfirmationState
    extends State<RecoveryPhraseConfirmation> {
  final _answers = [TextEditingController(), TextEditingController()];
  late final List<int> _indices;

  @override
  void initState() {
    super.initState();
    final random = Random.secure();
    final first = random.nextInt(12);
    var second = random.nextInt(11);
    if (second >= first) second++;
    _indices = [first, second]..sort();
  }

  void _check() {
    final words = widget.phrase.trim().split(RegExp(r'\s+'));
    widget.onChanged(
      words.length == 12 &&
          [0, 1].every(
            (i) =>
                _answers[i].text.trim().toLowerCase() ==
                words[_indices[i]].toLowerCase(),
          ),
    );
  }

  @override
  void dispose() {
    for (final answer in _answers) {
      answer.clear();
      answer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const Text('Confirm two words from your saved recovery phrase.'),
      for (var i = 0; i < 2; i++)
        TextField(
          key: Key('recovery-word-${_indices[i]}'),
          controller: _answers[i],
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          enableIMEPersonalizedLearning: false,
          decoration: InputDecoration(labelText: 'Word ${_indices[i] + 1}'),
          onChanged: (_) => _check(),
        ),
    ],
  );
}
