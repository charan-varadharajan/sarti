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
    this.nativeAi,
    this.emailInbox,
    this.onBackup,
    this.onGuardians,
    this.canWrite = true,
    this.canManageChildren = true,
  });

  final CalendarController controller;
  final CloudAiConsentController? cloudAiConsent;
  final NativeEventAiProvider? nativeAi;
  final EmailSuggestionInbox? emailInbox;
  final VoidCallback? onBackup;
  final VoidCallback? onGuardians;
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
            if (onGuardians != null)
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
            if (emailInbox != null && canWrite)
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
            if (nativeAi != null && canWrite)
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
            if (family.openConflicts > 0 && canWrite)
              IconButton(
                tooltip: 'Resolve conflicts',
                onPressed: () => _showConflicts(context),
                icon: Badge(
                  label: Text('${family.openConflicts}'),
                  child: const Icon(Icons.merge_type),
                ),
              ),
            if (canManageChildren)
              IconButton(
                tooltip: 'Add child',
                onPressed: () => _addChild(context),
                icon: const Icon(Icons.person_add_alt_1),
              ),
          ],
        ),
        floatingActionButton: !canWrite
            ? null
            : FloatingActionButton.extended(
                onPressed: () => _editEvent(context),
                icon: const Icon(Icons.add),
                label: const Text('Event'),
              ),
        body: Column(
          children: [
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
                onSelectionChanged: (value) =>
                    controller.setRange(value.single),
              ),
            ),
            Expanded(
              child: FamilyCalendarView(
                family: family,
                range: controller.range,
                timezone: controller.timezone,
                readOnly: !canWrite,
                onEdit: (event) => canWrite
                    ? _editEvent(context, event)
                    : _viewEvent(context, event),
                onCancel: (event) {
                  if (canWrite) controller.cancel(event);
                },
                onDelete: (event) {
                  if (canWrite) controller.delete(event);
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
      provider: nativeAi!,
    );
    if (saved != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Event added'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => controller.delete(saved),
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

  Future<void> _addChild(BuildContext context) async {
    final name = TextEditingController();
    final cloudAlias = TextEditingController();
    var shareProfile = false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a child'),
        content: StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: cloudAlias,
                decoration: const InputDecoration(
                  labelText: 'Private AI alias (optional)',
                  hintText: 'Example: happy-frog-4821',
                  helperText: 'Stored and synchronized encrypted',
                ),
              ),
              CheckboxListTile(
                key: const Key('share-child-profile'),
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Share profile with current calendar guardians',
                ),
                subtitle: const Text(
                  'Grants read access when this child first syncs.',
                ),
                value: shareProfile,
                onChanged: (value) =>
                    setState(() => shareProfile = value ?? false),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (accepted == true && name.text.trim().isNotEmpty) {
      try {
        controller.addChild(
          name.text,
          0xFF8E6CEF,
          cloudAlias: cloudAlias.text,
          shareWithCalendarGuardians: shareProfile,
        );
      } on ArgumentError catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error.message?.toString() ?? 'Invalid alias'),
            ),
          );
        }
      }
    }
  }

  Future<void> _editEvent(BuildContext context, [CalendarEvent? event]) async {
    final family = controller.family!;
    final title = TextEditingController(text: event?.title);
    final location = tz.getLocation(controller.timezone);
    var start =
        event?.localStart ??
        tz.TZDateTime.now(location).add(const Duration(hours: 1));
    var recurring = event?.recurrence != null;
    var selectedChildren = {...?event?.childIds};
    var pickup = event?.pickupGuardianId;
    final accepted = await showDialog<bool>(
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
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                ListTile(
                  title: const Text('Starts'),
                  subtitle: Text(start.toString()),
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
                SwitchListTile(
                  title: const Text('Repeat weekly'),
                  value: recurring,
                  onChanged: (value) => setState(() => recurring = value),
                ),
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
                  onChanged: (value) => pickup = value,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && title.text.trim().isNotEmpty) {
      controller.save(
        id: event?.id,
        title: title.text.trim(),
        localStart: start,
        durationMinutes: event?.durationMinutes ?? 60,
        childIds: selectedChildren.toList(),
        pickupGuardianId: pickup,
        recurrence: recurring
            ? RecurrenceRule(
                frequency: RecurrenceFrequency.weekly,
                weekdays: {start.weekday},
              )
            : null,
      );
    }
  }

  Future<void> _showConflicts(BuildContext context) async {
    final conflicts = controller.repository.openConflicts();
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
              onPressed: () => controller.createFamily('My family', 'Me'),
              child: const Text('Create family'),
            ),
          ],
        ),
      ),
    ),
  );
}
