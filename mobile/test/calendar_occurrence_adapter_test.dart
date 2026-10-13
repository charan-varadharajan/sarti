import 'package:flutter_test/flutter_test.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/features/calendar/domain/calendar_event.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_occurrence_adapter.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

CalendarEvent event({
  String id = 'event',
  String familyId = 'family',
  String resourceId = 'calendar',
  required DateTime start,
  int duration = 120,
  bool deleted = false,
  EventStatus status = EventStatus.scheduled,
  RecurrenceRule? recurrence,
}) => CalendarEvent(
  id: id,
  householdId: familyId,
  calendarResourceId: resourceId,
  title: 'Prepared activity',
  localStart: start,
  timezone: 'America/Vancouver',
  durationMinutes: duration,
  childIds: const [],
  revision: 1,
  updatedAt: DateTime.utc(2026),
  deleted: deleted,
  status: status,
  recurrence: recurrence,
);

FamilyCalendar family(List<CalendarEvent> events) => FamilyCalendar(
  householdId: 'family',
  name: 'Synthetic family',
  calendarResourceId: 'calendar',
  children: const [],
  guardians: const [],
  events: events,
  openConflicts: 0,
);

void main() {
  setUpAll(tz_data.initializeTimeZones);
  tz.TZDateTime date(
    int year,
    int month,
    int day, [
    int hour = 0,
    int minute = 0,
  ]) => tz.TZDateTime(
    tz.getLocation('America/Vancouver'),
    year,
    month,
    day,
    hour,
    minute,
  );

  test('CAL-GRID-UNIT-001 includes overnight carry-in but excludes exact end boundary', () {
    final data = family([event(start: date(2026, 10, 11, 23))]);
    final occurrences = calendarDisplayOccurrences(
      data,
      date(2026, 10, 12),
      date(2026, 10, 13),
    );
    expect(occurrences, hasLength(1));
    expect(
      occurrenceTimeLabel(occurrences.single, 'America/Vancouver'),
      '23:00–10/12 01:00',
    );
    expect(
      calendarDisplayOccurrences(
        data,
        date(2026, 10, 12, 1),
        date(2026, 10, 13),
      ),
      isEmpty,
    );
  });

  test('CAL-GRID-SEC-001 excludes other family/resource, cancellation and tombstones', () {
    final start = date(2026, 10, 12, 9);
    final occurrences = calendarDisplayOccurrences(
      family([
        event(id: 'valid', start: start),
        event(id: 'outsider', familyId: 'other', start: start),
        event(id: 'wrong-resource', resourceId: 'other', start: start),
        event(id: 'deleted', deleted: true, start: start),
        event(id: 'cancelled', status: EventStatus.cancelled, start: start),
      ]),
      date(2026, 10, 12),
      date(2026, 10, 13),
    );
    expect(occurrences.map((item) => item.event.id), ['valid']);
    expect(occurrences.single.interaction.allowRescheduling, isFalse);
    expect(occurrences.single.interaction.allowStartResize, isFalse);
    expect(occurrences.single.interaction.allowEndResize, isFalse);
  });

  test('CAL-GRID-UNIT-002 preserves elapsed duration and wall-clock recurrence across DST', () {
    final data = family([
      event(
        start: date(2026, 3, 1, 1, 30),
        duration: 120,
        recurrence: const RecurrenceRule(frequency: RecurrenceFrequency.weekly),
      ),
    ]);
    final occurrences = calendarDisplayOccurrences(
      data,
      date(2026, 3, 1),
      date(2026, 3, 9),
    );
    expect(occurrences, hasLength(2));
    expect(occurrences.map((item) => item.duration.inMinutes), [120, 120]);
    expect(
      occurrenceTimeLabel(occurrences.last, 'America/Vancouver'),
      '01:30 PST–04:30 PDT',
    );
    expect(occurrences.map((item) => item.id).toSet(), hasLength(2));
    expect(occurrenceTimeLabel(occurrences.last, 'UTC'), '09:30–11:30');
    expect(data.events.single.localStart.hour, 1);
  });

  test('CAL-GRID-UNIT-003 disambiguates repeated fall-back clock labels', () {
    final occurrence = CalendarDisplayOccurrence(
      event: event(start: date(2026, 11, 1, 0, 30)),
      start: date(2026, 11, 1, 0, 30),
    );
    expect(occurrence.duration.inMinutes, 120);
    expect(
      occurrenceTimeLabel(occurrence, 'America/Vancouver'),
      '00:30 PDT–01:30 PST',
    );
  });
}
