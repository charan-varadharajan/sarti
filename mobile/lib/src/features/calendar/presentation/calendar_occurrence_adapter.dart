import 'package:kalender/kalender.dart' as k;
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/features/calendar/domain/calendar_event.dart';
import 'package:sarti_mobile/src/features/calendar/domain/recurrence.dart';
import 'package:timezone/timezone.dart' as tz;

/// Ephemeral display object. It never writes calendar or sync state.
class CalendarDisplayOccurrence extends k.KalenderEvent {
  CalendarDisplayOccurrence({
    required this.event,
    required super.start,
    DateTime? end,
  }) : super(
         id: '${event.id}@${start.toUtc().microsecondsSinceEpoch}',
         end:
             end ?? start.toUtc().add(Duration(minutes: event.durationMinutes)),
         interaction: k.EventInteraction.allowNone(),
       );

  final CalendarEvent event;

  @override
  CalendarDisplayOccurrence copyWithData({
    required DateTime start,
    required DateTime end,
  }) => CalendarDisplayOccurrence(event: event, start: start, end: end);
}

List<CalendarDisplayOccurrence> calendarDisplayOccurrences(
  FamilyCalendar family,
  DateTime rangeStart,
  DateTime rangeEnd,
) {
  final result = <CalendarDisplayOccurrence>[];
  for (final event in family.events) {
    if (event.householdId != family.householdId ||
        event.calendarResourceId != family.calendarResourceId ||
        event.durationMinutes <= 0) {
      continue;
    }
    // Include an occurrence that started earlier but continues into this range.
    final lookback = Duration(minutes: event.durationMinutes);
    for (final occurrence in occurrencesBetween(
      event,
      rangeStart.toUtc().subtract(lookback),
      rangeEnd.toUtc(),
    )) {
      final display = CalendarDisplayOccurrence(
        event: event,
        start: occurrence.startsAt,
      );
      if (display.end.isAfter(rangeStart.toUtc())) result.add(display);
    }
  }
  result.sort((a, b) {
    final time = a.start.compareTo(b.start);
    return time == 0 ? a.id.compareTo(b.id) : time;
  });
  return result;
}

String occurrenceTimeLabel(CalendarDisplayOccurrence occurrence, String zone) {
  final location = tz.getLocation(zone);
  final start = tz.TZDateTime.from(occurrence.start, location);
  final end = tz.TZDateTime.from(occurrence.end, location);
  String clock(DateTime date) =>
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  final differentDay =
      start.year != end.year ||
      start.month != end.month ||
      start.day != end.day;
  final endDate = differentDay ? '${end.month}/${end.day} ' : '';
  final offsetChanged = start.timeZoneOffset != end.timeZoneOffset;
  final startZone = offsetChanged ? ' ${start.timeZoneName}' : '';
  final endZone = offsetChanged ? ' ${end.timeZoneName}' : '';
  return '${clock(start)}$startZone–$endDate${clock(end)}$endZone';
}
