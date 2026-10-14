import 'package:sarti_mobile/src/features/calendar/domain/calendar_event.dart';

/// A parsed time-of-day with no timezone attached.
class ParsedTime {
  const ParsedTime(this.hour, this.minute);
  final int hour;
  final int minute;

  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// Recurrence hint extracted from natural language.
enum RecurrenceHint { daily, weekly, monthly }

/// Structured output from the parser. All fields are nullable — the parser
/// never fabricates a value it cannot extract with confidence.
class EventProposal {
  const EventProposal({
    required this.rawInput,
    this.title,
    this.date,
    this.timeOfDay,
    this.location,
    this.recurrenceFrequency,
    this.recurrenceWeekday,
    this.childNameTokens = const [],
    this.guardianNameTokens = const [],
    this.requiresTimeConfirmation = false,
    this.durationMinutes,
    this.endTimeOfDay,
    this.hasExplicitDuration = false,
    this.requiresDurationConfirmation = false,
  });

  final String rawInput;
  final String? title;
  final DateTime? date;
  final ParsedTime? timeOfDay;
  final String? location;
  final RecurrenceHint? recurrenceFrequency;

  /// ISO weekday (1=Monday … 7=Sunday), null if not specified.
  final int? recurrenceWeekday;
  final List<String> childNameTokens;
  final List<String> guardianNameTokens;

  /// True when the input contained a clock time without enough information to
  /// distinguish morning from afternoon/evening.
  final bool requiresTimeConfirmation;
  final int? durationMinutes;
  final ParsedTime? endTimeOfDay;
  final bool hasExplicitDuration;
  final bool requiresDurationConfirmation;

  /// True when enough information exists to show a confirmation UI.
  bool get isActionable => title != null && title!.isNotEmpty;

  /// Converts to a [RecurrenceRule] for use in [CalendarEvent], if possible.
  RecurrenceRule? toRecurrenceRule() {
    if (recurrenceFrequency == null) return null;
    return RecurrenceRule(
      frequency: switch (recurrenceFrequency!) {
        RecurrenceHint.daily => RecurrenceFrequency.daily,
        RecurrenceHint.weekly => RecurrenceFrequency.weekly,
        RecurrenceHint.monthly => RecurrenceFrequency.monthly,
      },
      weekdays: recurrenceWeekday != null ? {recurrenceWeekday!} : const {},
    );
  }
}

/// Abstract interface — deterministic parser is the default implementation.
/// Future AI backends (on-device LLM, cloud assist) implement this interface.
/// External implementations must apply the local pseudonymization boundary in
/// ADR-036 before transmitting minimized scheduling tokens.
abstract interface class AiProvider {
  EventProposal parse(String input, {DateTime? now});
}

final _namedTime = RegExp(r'\b(noon|midnight)\b', caseSensitive: false);
final _duration = RegExp(
  r'\bfor\s+(\d+(?:\.\d+)?)\s*(hours?|hrs?|minutes?|mins?)\b',
  caseSensitive: false,
);
final _clock = RegExp(
  r'\b(?:\d{1,2}(?::\d{2})?\s*(?:am|pm)|\d{1,2}:\d{2}|noon|midnight|at\s+\d{1,2}(?![:\d]|\s*(?:am|pm)))\b',
  caseSensitive: false,
);

// ── Weekday helpers ──────────────────────────────────────────────────────────

const _weekdayNames = {
  'monday': DateTime.monday,
  'tuesday': DateTime.tuesday,
  'wednesday': DateTime.wednesday,
  'thursday': DateTime.thursday,
  'friday': DateTime.friday,
  'saturday': DateTime.saturday,
  'sunday': DateTime.sunday,
};

// ── Regex patterns ───────────────────────────────────────────────────────────

// 12-hour: "5pm", "5 PM", "5:30pm", "5:30 PM"
final _time12 = RegExp(
  r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b',
  caseSensitive: false,
);

// 24-hour: "14:30"
final _time24 = RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)\b');

// Bare hour: "at 4" (no am/pm)
final _bareHour = RegExp(r'\bat\s+(\d{1,2})\b');

// Relative date keywords
final _tomorrow = RegExp(r'\btomorrow\b', caseSensitive: false);
final _today = RegExp(r'\btoday\b', caseSensitive: false);

// Weekday in recurrence context: "every Tuesday"
final _everyWeekday = RegExp(
  r'\bevery\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b',
  caseSensitive: false,
);

// Bare weekday reference: "on Friday", "this Friday", or just "Friday"
final _bareWeekday = RegExp(
  r'\b(?:on\s+|this\s+)?(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b',
  caseSensitive: false,
);

// Recurrence without specific weekday
final _everyDay = RegExp(r'\bevery\s+day\b', caseSensitive: false);
final _everyWeek = RegExp(r'\bevery\s+week\b', caseSensitive: false);

// Location: "in <ProperNoun>" — stops before a digit or end
final _locationIn = RegExp(
  r'\bin\s+([A-Z][A-Za-z]+(?:\s+[A-Z][A-Za-z]+)*)(?=\s+at\s+\d|\s+on\s+|\s+every\s+|$)',
);

// Location: "at <ProperNoun>" — only when followed by another "at <time>" or end
final _locationAt = RegExp(
  r'\bat\s+([A-Z][A-Za-z]+(?:\s+[A-Z][A-Za-z]+)*)\s+at\s+\d',
);

// "X has <event>" pattern
final _hasPattern = RegExp(
  r'^([A-Z][a-z]+)(?:\s+and\s+([A-Z][a-z]+))?\s+(?:has|have)\s+(.+)',
  caseSensitive: false,
);

// "Remind <guardian> to <action>" pattern
final _remindPattern = RegExp(
  r'\bremind\s+([A-Z][a-z]+)\s+to\s+(.+?)(?:\s+at\s+\d|$)',
  caseSensitive: false,
);

// Possessive: "Mia's birthday"
final _possessivePattern = RegExp(r"^([A-Z][a-z]+)'s\s+(.+)");

// "and" joining two names: "Mia and Jithu"
final _andNames = RegExp(r'\b([A-Z][a-z]+)\s+and\s+([A-Z][a-z]+)\b');

/// Pure-Dart deterministic event parser (ADR-023).
/// No network calls, no external dependencies.
class DeterministicEventParser implements AiProvider {
  const DeterministicEventParser();

  // Strips all time/date/recurrence/location keywords and cleans whitespace.
  String _stripKeywords(String s) => s
      .replaceAll(_duration, '')
      .replaceAll(_namedTime, '')
      .replaceAll(_time12, '')
      .replaceAll(_time24, '')
      .replaceAll(_bareHour, '')
      .replaceAll(_everyWeekday, '')
      .replaceAll(_everyDay, '')
      .replaceAll(_everyWeek, '')
      .replaceAll(_bareWeekday, '')
      .replaceAll(_tomorrow, '')
      .replaceAll(_today, '')
      .replaceAll(_locationIn, '')
      .replaceAll(_locationAt, '')
      .replaceAll(RegExp(r'\bat\b', caseSensitive: false), '')
      .replaceAll(RegExp(r'\bin\b', caseSensitive: false), '')
      .replaceAll(RegExp(r'\bon\b', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();

  List<EventProposal> parseAll(String input, {DateTime? now}) {
    final parts = input.split(RegExp(r'\s+and\s+|;\s*', caseSensitive: false));
    if (parts.length == 1 ||
        (!_clock.hasMatch(parts.first) &&
            !parts.every(
              (p) =>
                  RegExp(r'\bhas\b|\bhave\b', caseSensitive: false).hasMatch(p),
            )) ||
        !parts.skip(1).any((p) => _clock.hasMatch(p))) {
      return [parse(input, now: now)];
    }
    final proposals = <EventProposal>[];
    String? sharedDate, activity;
    for (var i = 0; i < parts.length; i++) {
      var text = parts[i].trim();
      if (i == 0) {
        sharedDate = RegExp(
          r'\b(today|tomorrow|(?:every\s+)?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday))\b',
          caseSensitive: false,
        ).firstMatch(text)?.group(0);
      } else {
        if (!RegExp(
              r'\b(today|tomorrow|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b',
              caseSensitive: false,
            ).hasMatch(text) &&
            sharedDate != null) {
          text = '$text $sharedDate';
        }
        final short = RegExp(
          r'^([A-Za-z][A-Za-z-]*)\s+at\b',
          caseSensitive: false,
        ).firstMatch(text);
        if (short != null && activity != null) {
          text =
              '${short.group(1)} has $activity ${text.substring(short.end - 2)}';
        }
      }
      final proposal = parse(text, now: now);
      proposals.add(proposal);
      if (i == 0 && proposal.title != null) activity = proposal.title;
    }
    return proposals;
  }

  @override
  EventProposal parse(String input, {DateTime? now}) {
    if (input.trim().isEmpty) return EventProposal(rawInput: input);

    final effective = now ?? DateTime.now();
    final working = input.trim();

    String? title;
    final childTokens = <String>[];
    final guardianTokens = <String>[];

    // ── pattern: "Remind Dad to pick up Mia at 3:30" ──────────────────────
    final remindMatch = _remindPattern.firstMatch(working);
    if (remindMatch != null) {
      guardianTokens.add(remindMatch.group(1)!);
      title = remindMatch.group(2)!.trim();
    }

    // ── pattern: "Mia's birthday in Thorpe Park at 11am" ──────────────────
    if (title == null) {
      final possMatch = _possessivePattern.firstMatch(working);
      if (possMatch != null) {
        childTokens.add(possMatch.group(1)!);
        title = _stripKeywords(possMatch.group(2)!);
      }
    }

    // ── pattern: "Mia has swimming every Tuesday at 5 PM" ─────────────────
    if (title == null) {
      final hasMatch = _hasPattern.firstMatch(working);
      if (hasMatch != null) {
        childTokens.add(hasMatch.group(1)!);
        if (hasMatch.group(2) != null) childTokens.add(hasMatch.group(2)!);
        title = _stripKeywords(hasMatch.group(3)!);
      }
    }

    // ── "Mia and Jithu have football" ─────────────────────────────────────
    if (childTokens.isEmpty) {
      final andMatch = _andNames.firstMatch(working);
      if (andMatch != null) {
        childTokens.add(andMatch.group(1)!);
        childTokens.add(andMatch.group(2)!);
      }
    }

    final forChild = RegExp(
      r'\bfor\s+([A-Za-z][A-Za-z-]*)\b',
      caseSensitive: false,
    ).firstMatch(working);
    if (forChild != null && !_duration.hasMatch(forChild.group(0)!)) {
      childTokens.add(forChild.group(1)!);
    }

    // ── fallback title ────────────────────────────────────────────────────
    title ??= _stripKeywords(working);
    if (forChild != null) {
      title = title.replaceAll(forChild.group(0)!, '').trim();
    }
    if (title.isEmpty) title = null;

    // ── time ──────────────────────────────────────────────────────────────
    ParsedTime? timeOfDay;
    var requiresTimeConfirmation = false;
    final t12 = _time12.firstMatch(working);
    if (t12 != null) {
      var hour = int.parse(t12.group(1)!);
      final minute = int.tryParse(t12.group(2) ?? '0') ?? 0;
      final ampm = t12.group(3)!.toLowerCase();
      if (ampm == 'pm' && hour != 12) hour += 12;
      if (ampm == 'am' && hour == 12) hour = 0;
      timeOfDay = ParsedTime(hour, minute);
    } else {
      final t24 = _time24.firstMatch(working);
      if (t24 != null) {
        final hour = int.parse(t24.group(1)!);
        final minute = int.parse(t24.group(2)!);
        if (hour == 0 || hour > 12) {
          timeOfDay = ParsedTime(hour, minute);
        } else {
          requiresTimeConfirmation = true;
        }
      } else {
        // bare hour without am/pm: "at 4"
        final bh = _bareHour.firstMatch(working);
        if (bh != null) {
          final h = int.parse(bh.group(1)!);
          if (h == 0 || (h > 12 && h <= 23)) {
            timeOfDay = ParsedTime(h, 0);
          } else if (h >= 1 && h <= 12) {
            requiresTimeConfirmation = true;
          }
        }
      }
    }

    final named = _namedTime.firstMatch(working);
    if (named != null) {
      timeOfDay = ParsedTime(
        named.group(1)!.toLowerCase() == 'noon' ? 12 : 0,
        0,
      );
    }
    if (timeOfDay != null &&
        (timeOfDay.hour > 23 ||
            timeOfDay.minute > 59 ||
            (t12 != null &&
                (int.parse(t12.group(1)!) < 1 ||
                    int.parse(t12.group(1)!) > 12)))) {
      timeOfDay = null;
      requiresTimeConfirmation = true;
    }
    ParsedTime? endTimeOfDay;
    int? durationMinutes;
    var requiresDurationConfirmation = false;
    final durations = _duration.allMatches(working).toList();
    if (durations.length == 1) {
      final d = durations.single;
      final minutes =
          double.parse(d.group(1)!) *
          (d.group(2)!.toLowerCase().startsWith('h') ? 60 : 1);
      if (minutes > 0 &&
          minutes <= 10080 &&
          minutes == minutes.roundToDouble()) {
        durationMinutes = minutes.toInt();
      } else {
        requiresDurationConfirmation = true;
      }
    } else if (durations.length > 1) {
      requiresDurationConfirmation = true;
    }
    final range = RegExp(
      r'\b(?:to|until|-)\s*(\d{1,2}(?::\d{2})?\s*(?:am|pm)|noon|midnight|\d{1,2}:\d{2})\b',
      caseSensitive: false,
    ).firstMatch(working);
    if (range != null && timeOfDay != null) {
      final end = parse('End at ${range.group(1)}', now: now).timeOfDay;
      endTimeOfDay = end;
      if (end == null) {
        requiresDurationConfirmation = true;
      } else {
        var difference =
            end.hour * 60 + end.minute - timeOfDay.hour * 60 - timeOfDay.minute;
        if (difference < 0) difference += 1440;
        if (difference == 0 ||
            (durationMinutes != null && difference != durationMinutes)) {
          requiresDurationConfirmation = true;
        } else {
          durationMinutes = difference;
        }
      }
      title = title
          ?.replaceAll(range.group(0)!, '')
          .replaceAll(RegExp(r'\b(?:from|to|until)\b'), '')
          .trim();
    } else if (_clock.allMatches(working).length > 1) {
      if (range != null) requiresDurationConfirmation = true;
      timeOfDay = null;
      requiresTimeConfirmation = true;
    }

    // ── date ──────────────────────────────────────────────────────────────
    DateTime? date;
    if (_tomorrow.hasMatch(working)) {
      final d = effective.add(const Duration(days: 1));
      date = DateTime(d.year, d.month, d.day);
    } else if (_today.hasMatch(working)) {
      date = DateTime(effective.year, effective.month, effective.day);
    } else {
      final strippedForDate = working.replaceAll(_everyWeekday, '');
      final wdMatch = _bareWeekday.firstMatch(strippedForDate);
      if (wdMatch != null) {
        final target = _weekdayNames[wdMatch.group(1)!.toLowerCase()]!;
        var diff = target - effective.weekday;
        if (diff <= 0) diff += 7;
        final next = effective.add(Duration(days: diff));
        date = DateTime(next.year, next.month, next.day);
      }
    }

    // ── recurrence ────────────────────────────────────────────────────────
    RecurrenceHint? recurrenceFrequency;
    int? recurrenceWeekday;

    if (_everyDay.hasMatch(working)) {
      recurrenceFrequency = RecurrenceHint.daily;
    } else {
      final ewdMatch = _everyWeekday.firstMatch(working);
      if (ewdMatch != null) {
        recurrenceFrequency = RecurrenceHint.weekly;
        recurrenceWeekday = _weekdayNames[ewdMatch.group(1)!.toLowerCase()];
      } else if (_everyWeek.hasMatch(working)) {
        recurrenceFrequency = RecurrenceHint.weekly;
      }
    }

    // ── location ──────────────────────────────────────────────────────────
    String? location;
    final locIn = _locationIn.firstMatch(working);
    if (locIn != null) {
      location = locIn.group(1)!.trim();
    } else {
      final locAt = _locationAt.firstMatch(working);
      if (locAt != null) location = locAt.group(1)!.trim();
    }

    return EventProposal(
      rawInput: input,
      title: title,
      date: date,
      timeOfDay: timeOfDay,
      location: location,
      recurrenceFrequency: recurrenceFrequency,
      recurrenceWeekday: recurrenceWeekday,
      childNameTokens: childTokens,
      guardianNameTokens: guardianTokens,
      requiresTimeConfirmation: requiresTimeConfirmation,
      durationMinutes: durationMinutes,
      endTimeOfDay: endTimeOfDay,
      hasExplicitDuration: durations.isNotEmpty,
      requiresDurationConfirmation: requiresDurationConfirmation,
    );
  }
}
