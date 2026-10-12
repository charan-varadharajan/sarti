import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/core/database/sarti_database.dart';
import 'package:sarti_mobile/src/core/ids.dart';
import 'package:sarti_mobile/src/features/ai/cloud_alias.dart';
import 'package:sarti_mobile/src/features/ai/event_parser.dart';
import 'package:sarti_mobile/src/features/ai/gemini_ai_provider.dart';
import 'package:sarti_mobile/src/features/ai/prompt_pseudonymizer.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';

void main() {
  test('child aliases are validated and differ from the display name', () {
    expect(
      CloudAlias.validate('Hanging-Frog-42', childName: 'Mia'),
      'hanging-frog-42',
    );
    expect(
      () => CloudAlias.validate('Mia', childName: 'Mia'),
      throwsArgumentError,
    );
    expect(
      () => CloudAlias.validate('mia-frog', childName: 'Mia'),
      throwsArgumentError,
    );
    expect(
      () => CloudAlias.validate('two words', childName: 'Mia'),
      throwsArgumentError,
    );
  });

  test('generated alias is stored locally and can be user selected', () {
    final database = SartiDatabase.open(':memory:', Uint8List(32));
    addTearDown(database.close);
    final repository = CalendarRepository(database, deviceId: newId());
    repository.createFamily(name: 'Family', ownerName: 'Parent');

    final generated = repository.addChild('Mia', 0xFF8E6CEF);
    final chosen = repository.addChild(
      'Jithu',
      0xFF8E6CEF,
      cloudAlias: 'quiet-otter-7312',
    );

    expect(generated.cloudAlias, isNot(equalsIgnoringCase('Mia')));
    expect(chosen.cloudAlias, 'quiet-otter-7312');
    expect(repository.load()!.cloudChildAliases, {
      'Jithu': 'quiet-otter-7312',
      'Mia': generated.cloudAlias,
    });
  });

  test(
    'prompt replaces child and location then restores structured output',
    () {
      const pseudonymizer = PromptPseudonymizer();
      final protected = pseudonymizer.protect(
        'Mia has swimming at Maple Ridge Leisure Centre at 5pm',
        childAliases: const {'Mia': 'hanging-frog-4821'},
        sensitiveLocations: const ['Maple Ridge Leisure Centre'],
      );

      expect(protected.text, isNot(contains('Mia')));
      expect(protected.text, isNot(contains('Maple Ridge Leisure Centre')));
      expect(
        protected.text,
        'hanging-frog-4821 has swimming at place-1 at 5pm',
      );
      expect(
        protected.restoreJson({
          'title': 'Swimming for hanging-frog-4821',
          'location': 'place-1',
          'childNameTokens': ['hanging-frog-4821'],
        }),
        {
          'title': 'Swimming for Mia',
          'location': 'Maple Ridge Leisure Centre',
          'childNameTokens': ['Mia'],
        },
      );
    },
  );

  test('name matching uses boundaries and ignores case', () {
    const pseudonymizer = PromptPseudonymizer();
    final protected = pseudonymizer.protect(
      'MIA visits Miami',
      childAliases: const {'Mia': 'quiet-panda-1234'},
    );

    expect(protected.text, 'quiet-panda-1234 visits Miami');
  });

  test('Gemini enrichment fails closed for an unmapped child token', () async {
    final provider = GeminiAiProvider('unused-test-key');
    const proposal = EventProposal(
      rawInput: 'Mia has swimming Tuesday at 5',
      title: 'Swimming',
      childNameTokens: ['Mia'],
    );

    final result = await provider.tryEnrich(
      proposal,
      childAliases: const {'Jithu': 'quiet-otter-7312'},
    );

    expect(identical(result, proposal), isTrue);
  });
}
