import 'dart:math' as math;

import 'calendar_event.dart';

import 'package:timezone/timezone.dart' as tz;

enum CalendarRetention {
  week('1 week'),
  month('1 month'),
  quarter('3 months'),
  year('1 year'),
  never('Never');

  const CalendarRetention(this.label);
  final String label;

  DateTime? cutoff(DateTime now, String zone) {
    if (this == never) return null;
    if (this == week) return now.toUtc().subtract(const Duration(days: 7));
    final local = tz.TZDateTime.from(now, tz.getLocation(zone));
    final months = this == month
        ? 1
        : this == quarter
        ? 3
        : 12;
    final target = DateTime(local.year, local.month - months);
    final day = math.min(
      local.day,
      DateTime(target.year, target.month + 1, 0).day,
    );
    return tz.TZDateTime(
      local.location,
      target.year,
      target.month,
      day,
      local.hour,
      local.minute,
      local.second,
      local.millisecond,
      local.microsecond,
    ).toUtc();
  }
}

/// Returns null unless completion is proved, including for bounded recurrence.
DateTime? completedCalendarEnd(CalendarEvent event) {
  final zone = tz.getLocation(event.timezone);
  var start = tz.TZDateTime(
    zone,
    event.localStart.year,
    event.localStart.month,
    event.localStart.day,
    event.localStart.hour,
    event.localStart.minute,
  );
  final rule = event.recurrence;
  if (rule == null) {
    return start.add(Duration(minutes: event.durationMinutes)).toUtc();
  }
  if (rule.count == null && rule.untilLocalDate == null) return null;
  final firstWeek = start.subtract(
    Duration(days: start.weekday - DateTime.monday),
  );
  DateTime? last;
  var generated = 0;
  for (var guard = 0; guard < 10000; guard++) {
    final civil = DateTime(start.year, start.month, start.day);
    if (rule.untilLocalDate != null && civil.isAfter(rule.untilLocalDate!)) {
      return last;
    }
    final weeks = start.difference(firstWeek).inDays ~/ 7;
    final allowed =
        rule.frequency != RecurrenceFrequency.weekly ||
        (weeks % rule.interval == 0 &&
            (rule.weekdays.isEmpty || rule.weekdays.contains(start.weekday)));
    if (allowed) {
      last = start.add(Duration(minutes: event.durationMinutes)).toUtc();
      generated++;
      if (rule.count != null && generated >= rule.count!) return last;
    }
    if (rule.frequency == RecurrenceFrequency.monthly) {
      final target = DateTime(start.year, start.month + rule.interval);
      start = tz.TZDateTime(
        zone,
        target.year,
        target.month,
        math.min(
          event.localStart.day,
          DateTime(target.year, target.month + 1, 0).day,
        ),
        event.localStart.hour,
        event.localStart.minute,
      );
    } else {
      final days = rule.frequency == RecurrenceFrequency.daily
          ? rule.interval
          : rule.weekdays.isEmpty
          ? 7 * rule.interval
          : 1;
      start = tz.TZDateTime(
        zone,
        start.year,
        start.month,
        start.day + days,
        event.localStart.hour,
        event.localStart.minute,
      );
    }
  }
  return null; // Never infer completion from the safety limit.
}

bool calendarHistoryExpired(
  CalendarEvent event,
  CalendarRetention period,
  DateTime now,
) {
  final cutoff = period.cutoff(now, event.timezone);
  if (cutoff == null) return false;
  final end = completedCalendarEnd(event);
  return end != null && !end.isAfter(now.toUtc()) && !end.isAfter(cutoff);
}
