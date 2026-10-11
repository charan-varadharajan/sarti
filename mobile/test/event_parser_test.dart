import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/features/ai/event_parser.dart';

void main() {
  group('DeterministicEventParser', () {
    late DeterministicEventParser parser;

    setUp(() => parser = DeterministicEventParser());

    // ── title extraction ──────────────────────────────────────────────────

    test('extracts simple title', () {
      final p = parser.parse('Swimming at 5pm');
      expect(p.title, 'Swimming');
    });

    test('extracts title with child token', () {
      final p = parser.parse('Mia has swimming every Tuesday at 5 PM');
      expect(p.title, 'swimming');
      expect(p.childNameTokens, contains('Mia'));
    });

    test('extracts title from remind pattern', () {
      final p = parser.parse('Remind Dad to pick up Mia at 3:30');
      expect(p.title, 'pick up Mia');
      expect(p.guardianNameTokens, contains('Dad'));
    });

    // ── time extraction ───────────────────────────────────────────────────

    test('parses 12-hour time with pm', () {
      final p = parser.parse('Football at 4pm');
      expect(p.timeOfDay?.hour, 16);
      expect(p.timeOfDay?.minute, 0);
    });

    test('parses 12-hour time with space before pm', () {
      final p = parser.parse('Swimming at 5 PM');
      expect(p.timeOfDay?.hour, 17);
      expect(p.timeOfDay?.minute, 0);
    });

    test('parses 24-hour time', () {
      final p = parser.parse('Meeting at 14:30');
      expect(p.timeOfDay?.hour, 14);
      expect(p.timeOfDay?.minute, 30);
    });

    test('parses half-hour time', () {
      final p = parser.parse('Pick up at 3:30');
      expect(p.timeOfDay?.hour, 3);
      expect(p.timeOfDay?.minute, 30);
    });

    test('leaves time null when absent', () {
      final p = parser.parse('Swimming practice');
      expect(p.timeOfDay, isNull);
    });

    // ── relative date ─────────────────────────────────────────────────────

    test('resolves tomorrow', () {
      final now = DateTime(2026, 10, 13); // Tuesday
      final p = parser.parse('Football practice tomorrow at 4', now: now);
      expect(p.date?.day, 14);
      expect(p.date?.month, 10);
    });

    test('resolves today', () {
      final now = DateTime(2026, 10, 13);
      final p = parser.parse('Swimming today at 5pm', now: now);
      expect(p.date?.day, 13);
    });

    test('resolves next weekday', () {
      final now = DateTime(2026, 10, 13); // Tuesday
      final p = parser.parse('Football on Friday', now: now);
      expect(p.date?.weekday, DateTime.friday);
    });

    test('leaves date null when absent', () {
      final p = parser.parse('Swimming at 5pm');
      expect(p.date, isNull);
    });

    // ── recurrence ────────────────────────────────────────────────────────

    test('detects every Tuesday weekly recurrence', () {
      final p = parser.parse('Mia has swimming every Tuesday at 5 PM');
      expect(p.recurrenceFrequency, RecurrenceHint.weekly);
      expect(p.recurrenceWeekday, DateTime.tuesday);
    });

    test('detects every day recurrence', () {
      final p = parser.parse('Morning run every day at 7am');
      expect(p.recurrenceFrequency, RecurrenceHint.daily);
    });

    test('detects every week without weekday', () {
      final p = parser.parse('Team meeting every week at 10am');
      expect(p.recurrenceFrequency, RecurrenceHint.weekly);
      expect(p.recurrenceWeekday, isNull);
    });

    test('no recurrence when absent', () {
      final p = parser.parse('Swimming tomorrow at 5pm');
      expect(p.recurrenceFrequency, isNull);
    });

    // ── location ──────────────────────────────────────────────────────────

    test('extracts at-location', () {
      final p = parser.parse("Mia's birthday at Thorpe Park at 11am Sunday");
      expect(p.location, 'Thorpe Park');
    });

    test('extracts in-location', () {
      final p = parser.parse('Football practice in Central Park at 4pm');
      expect(p.location, 'Central Park');
    });

    test('leaves location null when absent', () {
      final p = parser.parse('Swimming at 5pm');
      expect(p.location, isNull);
    });

    // ── child / guardian name tokens ──────────────────────────────────────

    test('extracts multiple child tokens', () {
      final p = parser.parse('Mia and Jithu have football at 4pm');
      expect(p.childNameTokens, containsAll(['Mia', 'Jithu']));
    });

    test('extracts guardian token from remind pattern', () {
      final p = parser.parse('Remind Dad to pick up Mia at 3:30');
      expect(p.guardianNameTokens, contains('Dad'));
    });

    // ── uncertainty ───────────────────────────────────────────────────────

    test('empty input returns all-null proposal', () {
      final p = parser.parse('');
      expect(p.title, isNull);
      expect(p.timeOfDay, isNull);
      expect(p.date, isNull);
    });

    test('does not fabricate time when only date given', () {
      final p = parser.parse('Swimming on Friday');
      expect(p.timeOfDay, isNull);
    });

    test('does not fabricate date when only time given', () {
      final p = parser.parse('Swimming at 5pm');
      expect(p.date, isNull);
    });

    // ── full sentence integration ─────────────────────────────────────────

    test('full sentence: Mia swimming every Tuesday', () {
      final p = parser.parse('Mia has swimming every Tuesday at 5 PM');
      expect(p.title, 'swimming');
      expect(p.timeOfDay?.hour, 17);
      expect(p.recurrenceFrequency, RecurrenceHint.weekly);
      expect(p.recurrenceWeekday, DateTime.tuesday);
      expect(p.childNameTokens, contains('Mia'));
    });

    test('full sentence: football tomorrow', () {
      final now = DateTime(2026, 10, 13);
      final p = parser.parse(
        'Jithu has football practice tomorrow at 4',
        now: now,
      );
      expect(p.title, 'football practice');
      // bare "at 4" has no am/pm — parser returns 4, does not fabricate pm
      expect(p.timeOfDay?.hour, 4);
      expect(p.date?.day, 14);
      expect(p.childNameTokens, contains('Jithu'));
    });

    test('full sentence: football tomorrow explicit pm', () {
      final now = DateTime(2026, 10, 13);
      final p = parser.parse(
        'Jithu has football practice tomorrow at 4pm',
        now: now,
      );
      expect(p.title, 'football practice');
      expect(p.timeOfDay?.hour, 16);
      expect(p.date?.day, 14);
      expect(p.childNameTokens, contains('Jithu'));
    });

    test('full sentence: birthday at venue', () {
      final p = parser.parse("Mia's birthday in Thorpe Park at 11am Sunday");
      expect(p.title, contains('birthday'));
      expect(p.location, 'Thorpe Park');
      expect(p.timeOfDay?.hour, 11);
      expect(p.childNameTokens, contains('Mia'));
    });
  });

  // ── EventProposal.isActionable ────────────────────────────────────────────

  group('EventProposal.isActionable', () {
    test('actionable when title and time present', () {
      final p = EventProposal(
        rawInput: 'Swimming at 5pm',
        title: 'Swimming',
        timeOfDay: const ParsedTime(17, 0),
      );
      expect(p.isActionable, isTrue);
    });

    test('not actionable when title missing', () {
      final p = EventProposal(
        rawInput: 'at 5pm',
        timeOfDay: const ParsedTime(17, 0),
      );
      expect(p.isActionable, isFalse);
    });
  });
}
