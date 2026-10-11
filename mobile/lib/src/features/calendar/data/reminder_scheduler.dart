import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sarti_mobile/src/features/calendar/domain/calendar_event.dart';
import 'package:sarti_mobile/src/features/calendar/domain/recurrence.dart';
import 'package:timezone/timezone.dart' as tz;

abstract interface class ReminderScheduler {
  Future<void> replaceFor(CalendarEvent event);
  Future<void> cancelFor(String eventId);
}

class LocalReminderScheduler implements ReminderScheduler {
  LocalReminderScheduler([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  Future<void> initialize() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }
  }

  @override
  Future<void> replaceFor(CalendarEvent event) async {
    await cancelFor(event.id);
    if (event.deleted || event.status == EventStatus.cancelled) return;
    final now = DateTime.now().toUtc();
    final occurrences = occurrencesBetween(
      event,
      now,
      now.add(const Duration(days: 60)),
    );
    var slot = 0;
    for (final occurrence in occurrences.take(32)) {
      for (final minutes in event.reminderMinutes) {
        final scheduled = occurrence.startsAt.subtract(
          Duration(minutes: minutes),
        );
        if (!scheduled.toUtc().isAfter(now)) continue;
        await _plugin.zonedSchedule(
          id: _notificationId(event.id, slot++),
          title: 'Family reminder',
          body: 'A family event is coming up.',
          scheduledDate: tz.TZDateTime.from(scheduled, tz.local),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'calendar_reminders',
              'Calendar reminders',
              channelDescription: 'Reminders created on this device',
            ),
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: event.id,
        );
      }
    }
  }

  @override
  Future<void> cancelFor(String eventId) async {
    for (var slot = 0; slot < 64; slot++) {
      await _plugin.cancel(id: _notificationId(eventId, slot));
    }
  }

  int _notificationId(String eventId, int slot) =>
      (Object.hash(eventId, slot) & 0x7fffffff);
}
