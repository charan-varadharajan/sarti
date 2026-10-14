import 'dart:convert';

import '../domain/calendar_retention.dart';

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
    this.clock = DateTime.now,
  }) {
    family = repository.load();
  }

  Future<void> Function(CalendarRetention period, int revision)?
  updateRetention;
  final CalendarRepository repository;
  final String timezone;
  final DateTime Function() clock;
  int _todayRequest = 0;
  int get todayRequest => _todayRequest;
  final void Function(FamilyCalendar family)? onFamilyCreated;
  final void Function()? onLocalMutation;
  final ReminderScheduler? reminders;
  FamilyCalendar? family;
  CalendarRange range = CalendarRange.today;

  bool get canManageFamily {
    final local = family;
    if (local == null) return false;
    final rows = repository.database.raw.select(
      'SELECT value FROM app_preferences WHERE key=?',
      ['family-access-${local.householdId}'],
    );
    if (rows.isEmpty) {
      return true; // Existing/offline owner before provisioning.
    }
    try {
      final access = jsonDecode(rows.single['value'] as String);
      return access is Map && access['role'] == 'owner';
    } on FormatException {
      return false;
    }
  }

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

  void goToToday() {
    range = CalendarRange.today;
    _todayRequest++; // Repeated taps are navigation intents, not range changes.
    notifyListeners();
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
    List<EventParticipant> participants = const [],
    bool adultAppointment = false,
    bool shareWithHousehold = false,
    String? reviewedSharedVector,
    List<int> reminderMinutes = const [30],
  }) {
    final current = family ?? (throw StateError('Create a family first.'));
    final existing = id == null
        ? null
        : current.events.where((event) => event.id == id).firstOrNull;
    final saved = CalendarEvent(
      id: id ?? newId(),
      householdId: current.householdId,
      calendarResourceId: adultAppointment
          ? repository.ensurePersonalCalendar()
          : current.calendarResourceId,
      participants: participants,
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
    if (adultAppointment) {
      repository.saveAdultAppointment(
        saved,
        share: shareWithHousehold,
        reviewedSharedVector: reviewedSharedVector,
      );
    } else {
      repository.saveEvent(saved);
    }
    reminders?.replaceFor(saved);
    refresh();
    onLocalMutation?.call();
    return saved;
  }

  void _saveChangedEvent(CalendarEvent event) {
    if (event.calendarResourceId == repository.personalResourceId) {
      repository.saveAdultAppointment(
        event,
        share: repository.isShared(event.id),
      );
    } else {
      repository.saveEvent(event);
    }
  }

  void cancel(CalendarEvent event) {
    _saveChangedEvent(
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
    _saveChangedEvent(
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

  List<String> applyRetention({required bool canAdminister}) {
    if (repository.database.raw
        .select(
          "SELECT 1 FROM app_preferences WHERE key='retention-recovery-pending'",
        )
        .isNotEmpty) {
      return [];
    }
    final removed = repository.sweepRetention(
      clock(),
      canAdminister: canAdminister,
    );
    refresh();
    return removed;
  }

  void resolveHistory(String id, {required bool keep, String? reviewedVector}) {
    repository.resolveRetentionConflict(
      id,
      keep: keep,
      reviewedVector: reviewedVector,
    );
    if (keep) {
      final restored = repository
          .load()
          ?.events
          .where((e) => e.id == id)
          .firstOrNull;
      if (restored != null) reminders?.replaceFor(restored);
    } else {
      reminders?.cancelFor(id);
    }
    refresh();
    onLocalMutation?.call();
  }

  void refresh() {
    final previous = family;
    family = repository.load();
    final currentIds = family?.events.map((e) => e.id).toSet() ?? <String>{};
    for (final event in previous?.events ?? <CalendarEvent>[]) {
      if (!currentIds.contains(event.id)) reminders?.cancelFor(event.id);
    }
    notifyListeners();
  }
}
