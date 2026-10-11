import 'dart:math' as math;

import 'package:sarti_mobile/src/features/calendar/domain/calendar_event.dart';
import 'package:timezone/timezone.dart' as tz;

class EventOccurrence {
  const EventOccurrence(this.eventId, this.startsAt);

  final String eventId;
  final tz.TZDateTime startsAt;
}

List<EventOccurrence> occurrencesBetween(
  CalendarEvent event,
  DateTime rangeStartUtc,
  DateTime rangeEndUtc,
) {
  if (event.deleted || event.status == EventStatus.cancelled) return const [];
  final location = tz.getLocation(event.timezone);
  final first = tz.TZDateTime(
    location,
    event.localStart.year,
    event.localStart.month,
    event.localStart.day,
    event.localStart.hour,
    event.localStart.minute,
  );
  final rule = event.recurrence;
  if (rule == null) {
    return first.toUtc().isBefore(rangeStartUtc) ||
            !first.toUtc().isBefore(rangeEndUtc)
        ? const []
        : [EventOccurrence(event.id, first)];
  }

  final results = <EventOccurrence>[];
  var candidate = first;
  final firstWeekStart = first.subtract(
    Duration(days: first.weekday - DateTime.monday),
  );
  var generated = 0;
  var guard = 0;
  while (candidate.toUtc().isBefore(rangeEndUtc) && guard++ < 10000) {
    final weekOffset = candidate.difference(firstWeekStart).inDays ~/ 7;
    final allowedWeekday =
        rule.frequency != RecurrenceFrequency.weekly ||
        (weekOffset % rule.interval == 0 &&
            (rule.weekdays.isEmpty ||
                rule.weekdays.contains(candidate.weekday)));
    if (allowedWeekday) {
      generated++;
      final withinCount = rule.count == null || generated <= rule.count!;
      final withinUntil =
          rule.untilLocalDate == null ||
          !DateTime(
            candidate.year,
            candidate.month,
            candidate.day,
          ).isAfter(rule.untilLocalDate!);
      if (!withinCount || !withinUntil) break;
      if (!candidate.toUtc().isBefore(rangeStartUtc)) {
        results.add(EventOccurrence(event.id, candidate));
      }
    }
    candidate = switch (rule.frequency) {
      RecurrenceFrequency.daily => tz.TZDateTime(
        location,
        candidate.year,
        candidate.month,
        candidate.day + rule.interval,
        event.localStart.hour,
        event.localStart.minute,
      ),
      RecurrenceFrequency.weekly when rule.weekdays.isNotEmpty => tz.TZDateTime(
        location,
        candidate.year,
        candidate.month,
        candidate.day + 1,
        event.localStart.hour,
        event.localStart.minute,
      ),
      RecurrenceFrequency.weekly => tz.TZDateTime(
        location,
        candidate.year,
        candidate.month,
        candidate.day + (7 * rule.interval),
        event.localStart.hour,
        event.localStart.minute,
      ),
      RecurrenceFrequency.monthly => _nextMonthly(
        location,
        candidate,
        event.localStart,
        rule.interval,
      ),
    };
  }
  return results;
}

tz.TZDateTime _nextMonthly(
  tz.Location location,
  tz.TZDateTime candidate,
  DateTime original,
  int interval,
) {
  final firstOfTarget = DateTime(candidate.year, candidate.month + interval);
  final lastDay = DateTime(firstOfTarget.year, firstOfTarget.month + 1, 0).day;
  return tz.TZDateTime(
    location,
    firstOfTarget.year,
    firstOfTarget.month,
    math.min(original.day, lastDay),
    original.hour,
    original.minute,
  );
}
