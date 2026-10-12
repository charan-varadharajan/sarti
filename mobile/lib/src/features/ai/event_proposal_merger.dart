import 'package:sarti_mobile/src/features/ai/event_parser.dart';

/// Validates untrusted model output and only fills fields the deterministic
/// parser left unresolved.
class EventProposalMerger {
  const EventProposalMerger();

  EventProposal merge(EventProposal base, Map<String, dynamic> json) {
    final title = base.title ?? _string(json['title']);
    final location = base.location ?? _string(json['location']);

    ParsedTime? timeOfDay = base.timeOfDay;
    if (timeOfDay == null && !base.requiresTimeConfirmation) {
      final hour = _integer(json['timeHour']);
      final minute = _integer(json['timeMinute']) ?? 0;
      if (hour != null &&
          hour >= 0 &&
          hour <= 23 &&
          minute >= 0 &&
          minute <= 59) {
        timeOfDay = ParsedTime(hour, minute);
      }
    }

    RecurrenceHint? recurrence = base.recurrenceFrequency;
    int? recurrenceWeekday = base.recurrenceWeekday;
    if (recurrence == null) {
      recurrence = switch (_string(json['recurrence'])) {
        'daily' => RecurrenceHint.daily,
        'weekly' => RecurrenceHint.weekly,
        'monthly' => RecurrenceHint.monthly,
        _ => null,
      };
      if (recurrence == RecurrenceHint.weekly && recurrenceWeekday == null) {
        final weekday = _integer(json['recurrenceWeekday']);
        if (weekday != null && weekday >= 1 && weekday <= 7) {
          recurrenceWeekday = weekday;
        }
      }
    }

    final childTokens = base.childNameTokens.isNotEmpty
        ? base.childNameTokens
        : _stringList(json['childNameTokens']);
    final guardianTokens = base.guardianNameTokens.isNotEmpty
        ? base.guardianNameTokens
        : _stringList(json['guardianNameTokens']);

    return EventProposal(
      rawInput: base.rawInput,
      title: title,
      date: base.date,
      timeOfDay: timeOfDay,
      location: location,
      recurrenceFrequency: recurrence,
      recurrenceWeekday: recurrenceWeekday,
      childNameTokens: childTokens,
      guardianNameTokens: guardianTokens,
      requiresTimeConfirmation: base.requiresTimeConfirmation,
    );
  }

  String? _string(dynamic value) =>
      value is String && value.isNotEmpty ? value : null;
  int? _integer(dynamic value) => value is int ? value : null;
  List<String> _stringList(dynamic value) =>
      value is List ? value.whereType<String>().toList() : const [];
}
