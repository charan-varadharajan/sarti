import 'dart:convert';

import 'package:timezone/timezone.dart' as tz;

enum EventStatus { scheduled, cancelled }

enum RecurrenceFrequency { daily, weekly, monthly }

class RecurrenceRule {
  const RecurrenceRule({
    required this.frequency,
    this.interval = 1,
    this.weekdays = const {},
    this.count,
    this.untilLocalDate,
  }) : assert(interval > 0),
       assert(count == null || count > 0);

  final RecurrenceFrequency frequency;
  final int interval;
  final Set<int> weekdays;
  final int? count;
  final DateTime? untilLocalDate;

  Map<String, Object?> toJson() => {
    'frequency': frequency.name,
    'interval': interval,
    'weekdays': weekdays.toList()..sort(),
    'count': count,
    'untilLocalDate': untilLocalDate?.toIso8601String(),
  };

  factory RecurrenceRule.fromJson(Map<String, Object?> json) => RecurrenceRule(
    frequency: RecurrenceFrequency.values.byName(json['frequency']! as String),
    interval: json['interval']! as int,
    weekdays: Set<int>.from(json['weekdays']! as List<Object?>),
    count: json['count'] as int?,
    untilLocalDate: json['untilLocalDate'] == null
        ? null
        : DateTime.parse(json['untilLocalDate']! as String),
  );
}

class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.householdId,
    required this.calendarResourceId,
    required this.title,
    required this.localStart,
    required this.timezone,
    required this.durationMinutes,
    required this.childIds,
    required this.revision,
    required this.updatedAt,
    this.notes,
    this.status = EventStatus.scheduled,
    this.recurrence,
    this.pickupGuardianId,
    this.dropoffGuardianId,
    this.reminderMinutes = const [],
    this.deleted = false,
  });

  final String id;
  final String householdId;
  final String calendarResourceId;
  final String title;
  final String? notes;
  final DateTime localStart;
  final String timezone;
  final int durationMinutes;
  final EventStatus status;
  final RecurrenceRule? recurrence;
  final List<String> childIds;
  final String? pickupGuardianId;
  final String? dropoffGuardianId;
  final List<int> reminderMinutes;
  final int revision;
  final DateTime updatedAt;
  final bool deleted;

  CalendarEvent copyWith({
    String? title,
    DateTime? localStart,
    String? timezone,
    int? durationMinutes,
    EventStatus? status,
    RecurrenceRule? recurrence,
    String? pickupGuardianId,
    String? dropoffGuardianId,
    List<String>? childIds,
    List<int>? reminderMinutes,
    int? revision,
    DateTime? updatedAt,
    bool? deleted,
  }) => CalendarEvent(
    id: id,
    householdId: householdId,
    calendarResourceId: calendarResourceId,
    title: title ?? this.title,
    notes: notes,
    localStart: localStart ?? this.localStart,
    timezone: timezone ?? this.timezone,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    status: status ?? this.status,
    recurrence: recurrence ?? this.recurrence,
    childIds: childIds ?? this.childIds,
    pickupGuardianId: pickupGuardianId ?? this.pickupGuardianId,
    dropoffGuardianId: dropoffGuardianId ?? this.dropoffGuardianId,
    reminderMinutes: reminderMinutes ?? this.reminderMinutes,
    revision: revision ?? this.revision,
    updatedAt: updatedAt ?? this.updatedAt,
    deleted: deleted ?? this.deleted,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'householdId': householdId,
    'calendarResourceId': calendarResourceId,
    'title': title,
    'notes': notes,
    'localStart': localStart.toIso8601String(),
    'timezone': timezone,
    'durationMinutes': durationMinutes,
    'status': status.name,
    'recurrence': recurrence?.toJson(),
    'childIds': childIds,
    'pickupGuardianId': pickupGuardianId,
    'dropoffGuardianId': dropoffGuardianId,
    'reminderMinutes': reminderMinutes,
    'revision': revision,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'deleted': deleted,
  };

  String encode() => jsonEncode(toJson());

  factory CalendarEvent.fromJson(Map<String, Object?> json) {
    final timezone = json['timezone']! as String;
    return CalendarEvent(
      id: json['id']! as String,
      householdId: json['householdId']! as String,
      calendarResourceId: json['calendarResourceId']! as String,
      title: json['title']! as String,
      notes: json['notes'] as String?,
      localStart: tz.TZDateTime.from(
        DateTime.parse(json['localStart']! as String),
        tz.getLocation(timezone),
      ),
      timezone: timezone,
      durationMinutes: json['durationMinutes']! as int,
      status: EventStatus.values.byName(json['status']! as String),
      recurrence: json['recurrence'] == null
          ? null
          : RecurrenceRule.fromJson(
              Map<String, Object?>.from(json['recurrence']! as Map),
            ),
      childIds: List<String>.from(json['childIds']! as List<Object?>),
      pickupGuardianId: json['pickupGuardianId'] as String?,
      dropoffGuardianId: json['dropoffGuardianId'] as String?,
      reminderMinutes: List<int>.from(
        json['reminderMinutes']! as List<Object?>,
      ),
      revision: json['revision']! as int,
      updatedAt: DateTime.parse(json['updatedAt']! as String),
      deleted: json['deleted']! as bool,
    );
  }
}
