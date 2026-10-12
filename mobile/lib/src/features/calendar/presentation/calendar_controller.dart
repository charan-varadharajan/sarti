import 'package:flutter/foundation.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/features/calendar/data/reminder_scheduler.dart';
import 'package:sarti_mobile/src/features/calendar/domain/calendar_event.dart';
import 'package:sarti_mobile/src/core/ids.dart';

enum CalendarRange { today, week, month }

class CalendarController extends ChangeNotifier {
  CalendarController(
    this.repository, {
    required this.timezone,
    this.onFamilyCreated,
    this.onLocalMutation,
    this.reminders,
  }) {
    family = repository.load();
  }

  final CalendarRepository repository;
  final String timezone;
  final void Function(FamilyCalendar family)? onFamilyCreated;
  final void Function()? onLocalMutation;
  final ReminderScheduler? reminders;
  FamilyCalendar? family;
  CalendarRange range = CalendarRange.today;

  void createFamily(String name, String ownerName) {
    family = repository.createFamily(name: name, ownerName: ownerName);
    onFamilyCreated?.call(family!);
    onLocalMutation?.call();
    notifyListeners();
  }

  void addChild(
    String name,
    int colorArgb, {
    String? cloudAlias,
    bool shareWithCalendarGuardians = false,
  }) {
    repository.addChild(
      name,
      colorArgb,
      cloudAlias: cloudAlias,
      shareWithCalendarGuardians: shareWithCalendarGuardians,
    );
    refresh();
    onLocalMutation?.call();
  }

  void setRange(CalendarRange value) {
    range = value;
    notifyListeners();
  }

  CalendarEvent save({
    String? id,
    required String title,
    String? notes,
    required DateTime localStart,
    required int durationMinutes,
    required List<String> childIds,
    RecurrenceRule? recurrence,
    String? pickupGuardianId,
    List<int> reminderMinutes = const [30],
  }) {
    final current = family ?? (throw StateError('Create a family first.'));
    final existing = id == null
        ? null
        : current.events.where((event) => event.id == id).firstOrNull;
    final saved = CalendarEvent(
      id: id ?? newId(),
      householdId: current.householdId,
      calendarResourceId: current.calendarResourceId,
      title: title,
      notes: notes,
      localStart: localStart,
      timezone: timezone,
      durationMinutes: durationMinutes,
      childIds: childIds,
      recurrence: recurrence,
      pickupGuardianId: pickupGuardianId,
      reminderMinutes: reminderMinutes,
      revision: (existing?.revision ?? 0) + 1,
      updatedAt: DateTime.now().toUtc(),
    );
    repository.saveEvent(saved);
    reminders?.replaceFor(saved);
    refresh();
    onLocalMutation?.call();
    return saved;
  }

  void cancel(CalendarEvent event) {
    repository.saveEvent(
      event.copyWith(
        status: EventStatus.cancelled,
        revision: event.revision + 1,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    reminders?.cancelFor(event.id);
    refresh();
    onLocalMutation?.call();
  }

  void delete(CalendarEvent event) {
    repository.saveEvent(
      event.copyWith(
        deleted: true,
        revision: event.revision + 1,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    reminders?.cancelFor(event.id);
    refresh();
    onLocalMutation?.call();
  }

  void resolve(String conflictId, {required bool useRemote}) {
    repository.resolveConflict(conflictId, useRemote: useRemote);
    refresh();
    onLocalMutation?.call();
  }

  void refresh() {
    family = repository.load();
    notifyListeners();
  }
}
