import 'dart:convert';

import '../../../core/network/sarti_api.dart';

import 'family_setup_screen.dart';
import 'family_management_screen.dart';
import 'calendar_retention_screen.dart';
import '../data/calendar_repository.dart';
import 'household_profiles_screen.dart';
import 'child_profile_editor.dart';
import 'event_duration_input.dart';

import 'package:flutter/material.dart';
import 'package:sarti_mobile/src/features/ai/cloud_ai_consent.dart';
import 'package:sarti_mobile/src/features/ai/cloud_ai_consent_dialog.dart';
import 'package:sarti_mobile/src/features/ai/native_ai_provider.dart';
import 'package:sarti_mobile/src/features/ai/natural_language_event_dialog.dart';
import 'package:sarti_mobile/src/features/calendar/domain/calendar_event.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/family_calendar_view.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_controller.dart';
import 'package:sarti_mobile/src/features/email/email_suggestion_inbox.dart';
import 'package:timezone/timezone.dart' as tz;

class CalendarScreen extends StatelessWidget {
  const CalendarScreen({
    super.key,
    required this.controller,
    this.cloudAiConsent,
    this.cloudApi,
    this.nativeAi,
    this.emailInbox,
    this.onBackup,
    this.onPersonalBackup,
    this.onGuardians,
    this.onRecovery,
    this.canWrite = true,
    this.canManageChildren = true,
  });

  final CalendarController controller;
  final CloudAiConsentController? cloudAiConsent;
  final SartiApiClient? cloudApi;
  final NativeEventAiProvider? nativeAi;
  final EmailSuggestionInbox? emailInbox;
  final VoidCallback? onBackup, onPersonalBackup;
  final VoidCallback? onGuardians, onRecovery;
  final bool canWrite, canManageChildren;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final family = controller.family;
      if (family == null) return _FamilyOnboarding(controller: controller);
      return Scaffold(
        appBar: AppBar(
          title: Text(family.name),
          actions: [
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (value) {
                if (value == 'family') {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => FamilyManagementScreen(
                        controller: controller,
                        onGuardians: onGuardians,
                      ),
                    ),
                  );
                }
                if (value == 'people' || value == 'pets') {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => HouseholdProfilesScreen(
                        controller: controller,
                        petsOnly: value == 'pets',
                        onGuardians: onGuardians,
                      ),
                    ),
                  );
                }
                if (value == 'retention') {
                  if (controller.repository.recoveryPending &&
                      onRecovery != null) {
                    onRecovery!();
                    return;
                  }
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          CalendarRetentionScreen(controller: controller),
                    ),
                  );
                }
                if (value == 'private-backup') onPersonalBackup?.call();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  enabled: !controller.repository.recoveryPending,
                  value: 'family',
                  child: const Text('Family'),
                ),
                PopupMenuItem(
                  enabled: !controller.repository.recoveryPending,
                  value: 'people',
                  child: Text('People'),
                ),
                PopupMenuItem(
                  enabled: !controller.repository.recoveryPending,
                  value: 'pets',
                  child: Text('Pets'),
                ),
                const PopupMenuItem(
                  value: 'retention',
                  child: Text('Calendar retention'),
                ),
                if (onPersonalBackup != null)
                  const PopupMenuItem(
                    value: 'private-backup',
                    child: Text('My private backup'),
                  ),
              ],
            ),
            if (onGuardians != null && !controller.repository.recoveryPending)
              IconButton(
                tooltip: "Family guardians",
                onPressed: onGuardians,
                icon: const Icon(Icons.group_outlined),
              ),
            if (onBackup != null)
              IconButton(
                tooltip: 'Encrypted backup',
                onPressed: onBackup,
                icon: const Icon(Icons.backup_outlined),
              ),
            if (emailInbox != null &&
                canWrite &&
                !controller.repository.recoveryPending)
              ListenableBuilder(
                listenable: emailInbox!,
                builder: (context, _) => IconButton(
                  tooltip: 'Email suggestions',
                  onPressed: () => _showEmailSuggestions(context),
                  icon: Badge(
                    isLabelVisible: emailInbox!.suggestions.isNotEmpty,
                    label: Text('${emailInbox!.suggestions.length}'),
                    child: const Icon(Icons.mark_email_unread_outlined),
                  ),
                ),
              ),
            if (nativeAi != null &&
                canWrite &&
                !controller.repository.recoveryPending)
              IconButton(
                tooltip: 'Add with natural language',
                onPressed: () => _addWithNaturalLanguage(context),
                icon: const Icon(Icons.auto_awesome_outlined),
              ),
            if (cloudAiConsent != null)
              ListenableBuilder(
                listenable: cloudAiConsent!,
                builder: (context, _) => IconButton(
                  tooltip: 'Privacy & AI',
                  onPressed: () =>
                      showCloudAiConsentDialog(context, cloudAiConsent!),
                  icon: Icon(
                    cloudAiConsent!.enabled
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off_outlined,
                  ),
                ),
              ),
            if (!controller.repository.recoveryPending &&
                family.openConflicts > 0 &&
                (canWrite || controller.repository.adultId != null))
              IconButton(
                tooltip: 'Resolve conflicts',
                onPressed: () => _showConflicts(context),
                icon: Badge(
                  label: Text('${family.openConflicts}'),
                  child: const Icon(Icons.merge_type),
                ),
              ),
            if (canManageChildren && !controller.repository.recoveryPending)
              IconButton(
                tooltip: 'Add child',
                onPressed: () => _addChild(context),
                icon: const Icon(Icons.person_add_alt_1),
              ),
          ],
        ),
        floatingActionButton:
            controller.repository.recoveryPending ||
                (!canWrite && controller.repository.adultId == null)
            ? null
            : FloatingActionButton.extended(
                onPressed: () => _chooseEventEntry(context),
                icon: const Icon(Icons.add),
                label: const Text('Event'),
              ),
        body: Column(
          children: [
            if (controller.repository.recoveryPending)
              Card(
                child: ListTile(
                  title: const Text('Restored calendar is paused'),
                  subtitle: const Text(
                    'Review recovered changes before editing or cleanup.',
                  ),
                  trailing: TextButton(
                    onPressed: onRecovery,
                    child: const Text('Review recovery'),
                  ),
                ),
              ),
            if (!controller.repository.recoveryPending &&
                controller.repository.retentionConflicts().isNotEmpty)
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        CalendarRetentionScreen(controller: controller),
                  ),
                ),
                icon: const Icon(Icons.history),
                label: const Text('Review retention conflicts'),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SegmentedButton<CalendarRange>(
                segments: const [
                  ButtonSegment(
                    value: CalendarRange.today,
                    label: Text('Today'),
                  ),
                  ButtonSegment(value: CalendarRange.week, label: Text('Week')),
                  ButtonSegment(
                    value: CalendarRange.month,
                    label: Text('Month'),
                  ),
                ],
                selected: {controller.range},
                // Flutter otherwise ignores pressing an already-selected segment.
                // Treat that request as navigation; selection always remains set.
                emptySelectionAllowed: controller.range == CalendarRange.today,
                onSelectionChanged: (value) {
                  if (value.isEmpty || value.single == CalendarRange.today) {
                    controller.goToToday();
                  } else {
                    controller.setRange(value.single);
                  }
                },
              ),
            ),
            Expanded(
              child: FamilyCalendarView(
                family: family,
                range: controller.range,
                timezone: controller.timezone,
                todayRequest: controller.todayRequest,
                clock: controller.clock,
                readOnly: !canWrite || controller.repository.recoveryPending,
                canEdit: (event) =>
                    !controller.repository.recoveryPending &&
                    (canWrite ||
                        event.calendarResourceId ==
                            controller.repository.personalResourceId),
                onEdit: (event) =>
                    !controller.repository.recoveryPending &&
                        (canWrite ||
                            event.calendarResourceId ==
                                controller.repository.personalResourceId)
                    ? _editEvent(context, event)
                    : _viewEvent(context, event),
                onCancel: (event) {
                  if (canWrite ||
                      event.calendarResourceId ==
                          controller.repository.personalResourceId) {
                    controller.cancel(event);
                  }
                },
                onDelete: (event) {
                  if (canWrite ||
                      event.calendarResourceId ==
                          controller.repository.personalResourceId) {
                    controller.delete(event);
                  }
                },
              ),
            ),
          ],
        ),
      );
    },
  );

  Future<void> _viewEvent(BuildContext context, CalendarEvent event) async {
    final start = tz.TZDateTime.from(
      event.localStart,
      tz.getLocation(event.timezone),
    );
    final end = tz.TZDateTime.from(
      start.toUtc().add(Duration(minutes: event.durationMinutes)),
      tz.getLocation(event.timezone),
    );
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(event.title),
        content: Text(
          '$start – $end${event.notes == null ? "" : "\n${event.notes}"}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _addWithNaturalLanguage(BuildContext context) async {
    final saved = await showNaturalLanguageEventDialog(
      context,
      controller: controller,
      provider: nativeAi ?? NativeEventAiProvider(),
      cloudApi: cloudApi,
      cloudConsent: cloudAiConsent,
    );
    if (saved != null && context.mounted) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          persist: false,
          duration: const Duration(seconds: 5),
          showCloseIcon: true,
          content: Text(
            saved.length == 1 ? 'Event added' : '${saved.length} events added',
          ),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              CalendarEvent? selected;
              if (saved.length == 1) {
                selected = saved.single;
              } else {
                selected = await showDialog<CalendarEvent>(
                  context: context,
                  builder: (context) => SimpleDialog(
                    title: const Text('Review a saved event'),
                    children: [
                      for (final event in saved)
                        SimpleDialogOption(
                          onPressed: () => Navigator.pop(context, event),
                          child: Text(event.title),
                        ),
                    ],
                  ),
                );
              }
              if (selected == null || !context.mounted) return;
              final current = controller.family?.events
                  .where((e) => e.id == selected!.id)
                  .firstOrNull;
              if (current == null) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('This event is no longer available.'),
                  ),
                );
                return;
              }
              await _editEvent(context, current);
            },
          ),
        ),
      );
    }
  }

  Future<void> _showEmailSuggestions(BuildContext context) async {
    final inbox = emailInbox!;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => ListenableBuilder(
        listenable: inbox,
        builder: (context, _) => SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Email suggestions',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Email is untrusted. Sarti interprets it on this phone and never changes the calendar without your approval.',
              ),
              if (inbox.suggestions.isEmpty)
                ListTile(
                  title: Text(
                    inbox.unavailable
                        ? 'Suggestions could not be refreshed. Try again later.'
                        : 'No pending suggestions',
                  ),
                ),
              for (final suggestion in inbox.suggestions)
                Card(
                  child: ListTile(
                    title: Text(
                      suggestion.subject.trim().isEmpty
                          ? 'Email suggestion'
                          : suggestion.subject,
                    ),
                    subtitle: Text('From ${suggestion.sender}'),
                    onTap: () async {
                      final saved = await showNaturalLanguageEventDialog(
                        context,
                        controller: controller,
                        provider: nativeAi ?? NativeEventAiProvider(),
                        initialInput: suggestion.interpretationInput,
                        sourceLabel:
                            'Suggested from email by ${suggestion.sender}',
                      );
                      if (saved != null) {
                        await inbox.dismiss(suggestion.id);
                        if (context.mounted) Navigator.pop(context);
                      }
                    },
                    trailing: IconButton(
                      tooltip: 'Dismiss suggestion',
                      onPressed: () => inbox.dismiss(suggestion.id),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _chooseEventEntry(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('add-event-manually'),
              leading: const Icon(Icons.edit_calendar),
              title: const Text('Enter event details'),
              onTap: () => Navigator.pop(context, 'manual'),
            ),
            if (canWrite)
              ListTile(
                key: const Key('describe-event'),
                leading: const Icon(Icons.auto_awesome_outlined),
                title: const Text('Describe an event'),
                onTap: () => Navigator.pop(context, 'describe'),
              ),
          ],
        ),
      ),
    );
    if (!context.mounted || controller.repository.recoveryPending) return;
    if (choice == 'manual') {
      await _editEvent(context);
    } else if (choice == 'describe' && canWrite) {
      await _addWithNaturalLanguage(context);
    }
  }

  Future<void> _addChild(BuildContext context) async {
    await showAddChildProfileDialog(context, controller);
  }

  Future<void> _editEvent(BuildContext context, [CalendarEvent? event]) async {
    final family = controller.family!;
    final title = TextEditingController(text: event?.title);
    final location = tz.getLocation(controller.timezone);
    var start =
        event?.localStart ??
        tz.TZDateTime.now(location).add(const Duration(hours: 1));
    final duration = TextEditingController(
      text: '${event?.durationMinutes ?? 60}',
    );
    var recurring = event?.recurrence != null;
    var selectedChildren = {...?event?.childIds};
    var pickup = event?.pickupGuardianId;
    final selectedParticipants = {
      for (final p in event?.participants ?? <EventParticipant>[]) p.id: p.kind,
    };
    var adultAppointment =
        event != null &&
        event.calendarResourceId == controller.repository.personalResourceId;
    var share = event != null && controller.repository.isShared(event.id);
    String? error;
    String? reviewedSharedVector;

    String fingerprint() => jsonEncode([
      title.text.trim(),
      start.toIso8601String(),
      int.tryParse(duration.text),
      recurring,
      (selectedChildren.toList()..sort()),
      pickup,
      (selectedParticipants.entries.map((p) => '${p.key}:${p.value}').toList()
        ..sort()),
      adultAppointment,
      share,
    ]);
    final initialFingerprint = fingerprint();
    bool dirty() => event == null || fingerprint() != initialFingerprint;
    bool valid() =>
        title.text.trim().isNotEmpty &&
        (int.tryParse(duration.text) ?? 0) > 0 &&
        (int.tryParse(duration.text) ?? 10081) <= 10080;
    final route = DialogRoute<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(event == null ? 'New event' : 'Edit event'),
          content: SingleChildScrollView(
            key: const Key('event-editor-scroll'),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  onChanged: (_) => setState(() {}),
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                ListTile(
                  title: const Text('Starts'),
                  subtitle: Text(
                    MaterialLocalizations.of(context).formatMediumDate(start),
                  ),
                  trailing: const Icon(Icons.schedule),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 365),
                      ),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                      initialDate: start,
                    );
                    if (date != null) {
                      setState(
                        () => start = DateTime(
                          date.year,
                          date.month,
                          date.day,
                          start.hour,
                          start.minute,
                        ),
                      );
                    }
                  },
                ),
                ListTile(
                  title: const Text('Start time'),
                  subtitle: Text(TimeOfDay.fromDateTime(start).format(context)),
                  onTap: () async {
                    final selected = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(start),
                    );
                    if (selected != null) {
                      setState(
                        () => start = DateTime(
                          start.year,
                          start.month,
                          start.day,
                          selected.hour,
                          selected.minute,
                        ),
                      );
                    }
                  },
                ),
                EventDurationInput(
                  controller: duration,
                  fieldKey: 'event-duration',
                  onChanged: () => setState(() {}),
                  helperText: event == null ? 'Default: 1 hour' : null,
                ),
                if (valid())
                  Text(
                    'Ends: ${formatEventEnd(context, tz.TZDateTime(tz.getLocation(event?.timezone ?? controller.timezone), start.year, start.month, start.day, start.hour, start.minute), int.parse(duration.text))}',
                  ),
                SwitchListTile(
                  title: const Text('Repeat weekly'),
                  value: recurring,
                  onChanged: (value) => setState(() => recurring = value),
                ),
                if (controller.repository.adultId != null ||
                    controller.canManageFamily)
                  SwitchListTile(
                    key: const Key('adult-appointment'),
                    title: const Text('My private appointment'),
                    subtitle: Text(
                      controller.repository.adultId == null
                          ? 'Encrypted on this phone. Authenticate to publish or recover this private draft.'
                          : 'Only you can read this unless you explicitly share a copy.',
                    ),
                    value: adultAppointment,
                    onChanged: event == null
                        ? (value) => setState(() {
                            adultAppointment = value;
                            share = false;
                          })
                        : null,
                  ),
                if (adultAppointment)
                  SwitchListTile(
                    key: const Key('share-adult-appointment'),
                    title: const Text('Share with household'),
                    subtitle: const Text(
                      'All calendar guardians can read the shared copy, including pickup details. Unsharing cannot erase previously seen information.',
                    ),
                    value: share,
                    onChanged: canWrite
                        ? (value) => setState(() => share = value)
                        : null,
                  ),
                for (final profile in family.participants)
                  CheckboxListTile(
                    key: Key('event-participant-${profile.id}'),
                    title: Text(profile.name),
                    subtitle: Text(profile.kind),
                    secondary: CircleAvatar(
                      backgroundColor: Color(profile.colorArgb),
                      child: Icon(
                        profile.kind == 'pet' ? Icons.pets : Icons.person,
                        color: Colors.black87,
                      ),
                    ),
                    value: selectedParticipants.containsKey(profile.id),
                    onChanged: (value) => setState(() {
                      if (value == true) {
                        selectedParticipants[profile.id] = profile.kind;
                      } else {
                        selectedParticipants.remove(profile.id);
                      }
                      if (event == null &&
                          profile.adultId ==
                              controller.repository.currentAdultId &&
                          value == true) {
                        adultAppointment = true;
                        share = false;
                      }
                    }),
                  ),
                if (error != null && adultAppointment && event != null)
                  TextButton(
                    key: const Key('review-household-copy'),
                    onPressed: () async {
                      final copy = controller.repository.householdCopy(
                        event.id,
                      );
                      if (copy == null) return;
                      final replace = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Review changed household copy'),
                          content: Text(
                            '${copy.event.title}\n${copy.event.localStart}\nPickup: ${copy.event.pickupGuardianId == null ? 'Unassigned' : 'Assigned'}\nYour private event is unchanged. Saving this preview will replace the household copy.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Keep reviewing'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Use my preview'),
                            ),
                          ],
                        ),
                      );
                      if (replace == true && context.mounted) {
                        setState(() {
                          reviewedSharedVector = copy.vector;
                          error = null;
                        });
                      }
                    },
                    child: const Text('Review household copy'),
                  ),
                if (error != null)
                  Text(error!, key: const Key('event-save-error')),
                for (final child in family.children)
                  CheckboxListTile(
                    key: Key('event-child-${child.id}'),
                    title: Text(child.name),
                    value: selectedChildren.contains(child.id),
                    onChanged: (value) => setState(() {
                      value == true
                          ? selectedChildren.add(child.id)
                          : selectedChildren.remove(child.id);
                    }),
                  ),
                DropdownButtonFormField<String?>(
                  initialValue: pickup,
                  decoration: const InputDecoration(
                    labelText: 'Pickup guardian',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Unassigned'),
                    ),
                    ...family.guardians.map(
                      (guardian) => DropdownMenuItem(
                        value: guardian.id,
                        child: Text(guardian.name),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => pickup = value),
                ),
              ],
            ),
          ),
          actions: [
            if (event != null)
              TextButton(
                onPressed: () {
                  final current = controller.family?.events
                      .where((e) => e.id == event.id)
                      .firstOrNull;
                  if (current != null && current.encode() != event.encode()) {
                    setState(
                      () => error = 'This event changed. Close and reopen it before deleting.',
                    );
                    return;
                  }
                  if (current != null) controller.delete(current);
                  Navigator.pop(context, true);
                },
                child: const Text('Delete'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed:
                  (!canWrite && (!adultAppointment || share)) ||
                      !dirty() ||
                      !valid()
                  ? null
                  : () {
                      try {
                        if (event != null &&
                            controller.family?.events
                                    .where((e) => e.id == event.id)
                                    .firstOrNull
                                    ?.encode() !=
                                event.encode()) {
                          throw StateError('Event changed; reopen it.');
                        }
                        controller.save(
                          id: event?.id,
                          title: title.text,
                          localStart: start,
                          eventTimezone: event?.timezone,
                          durationMinutes: int.parse(duration.text),
                          notes: event?.notes,
                          childIds: selectedChildren.toList(),
                          participants: [
                            for (final p in selectedParticipants.entries)
                              EventParticipant(id: p.key, kind: p.value),
                          ],
                          adultAppointment: adultAppointment,
                          shareWithHousehold: share,
                          reviewedSharedVector: reviewedSharedVector,
                          pickupGuardianId: pickup,
                          recurrence:
                              recurring == (event?.recurrence != null) &&
                                  event?.recurrence != null
                              ? event!.recurrence
                              : recurring
                              ? RecurrenceRule(
                                  frequency: RecurrenceFrequency.weekly,
                                  weekdays: {start.weekday},
                                )
                              : null,
                        );
                        Navigator.pop(context, true);
                      } catch (_) {
                        setState(
                          () => error = 'Could not save. Check your details and review any changes to the household copy.',
                        );
                      }
                    },
              child: Text(
                adultAppointment && share ? 'Save and share' : 'Save',
              ),
            ),
          ],
        ),
      ),
    );
    final accepted = await Navigator.of(context).push(route);
    await route.completed;
    title.dispose();
    duration.dispose();
    if (accepted != true) return;
  }

  Future<void> _showConflicts(BuildContext context) async {
    final conflicts = controller.repository
        .openConflicts()
        .where(
          (c) =>
              canWrite ||
              c.local.calendarResourceId ==
                  controller.repository.personalResourceId,
        )
        .toList();
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Choose the version to keep',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          for (final conflict in conflicts)
            Card(
              child: Column(
                children: [
                  ListTile(
                    title: Text(conflict.local.title),
                    subtitle: const Text('This device'),
                  ),
                  ListTile(
                    title: Text(conflict.remote.title),
                    subtitle: const Text('Other device'),
                  ),
                  OverflowBar(
                    children: [
                      TextButton(
                        onPressed: () {
                          controller.resolve(conflict.id, useRemote: false);
                          Navigator.pop(context);
                        },
                        child: const Text('Keep this device'),
                      ),
                      FilledButton(
                        onPressed: () {
                          controller.resolve(conflict.id, useRemote: true);
                          Navigator.pop(context);
                        },
                        child: const Text('Use other device'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _FamilyOnboarding extends StatelessWidget {
  const _FamilyOnboarding({required this.controller});
  final CalendarController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Your family calendar',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            const Text(
              'Start with the calendar. You can add family details as you go.',
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => FamilySetupScreen(controller: controller),
                ),
              ),
              child: const Text('Create family'),
            ),
          ],
        ),
      ),
    ),
  );
}
