import 'package:flutter/material.dart';
import 'package:sarti_mobile/src/features/calendar/domain/calendar_event.dart';
import 'package:sarti_mobile/src/features/calendar/domain/recurrence.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_controller.dart';

class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key, required this.controller});

  final CalendarController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final family = controller.family;
      if (family == null) return _FamilyOnboarding(controller: controller);
      final visibleEvents = _visibleEvents(family.events);
      return Scaffold(
        appBar: AppBar(
          title: Text(family.name),
          actions: [
            if (family.openConflicts > 0)
              IconButton(
                tooltip: 'Resolve conflicts',
                onPressed: () => _showConflicts(context),
                icon: Badge(
                  label: Text('${family.openConflicts}'),
                  child: const Icon(Icons.merge_type),
                ),
              ),
            IconButton(
              tooltip: 'Add child',
              onPressed: () => _addChild(context),
              icon: const Icon(Icons.person_add_alt_1),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
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
              child: visibleEvents.isEmpty
                  ? const _EmptyCalendar()
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                      itemCount: visibleEvents.length,
                      itemBuilder: (context, index) {
                        final item = visibleEvents[index];
                        final event = item.event;
                        final child = family.children
                            .where((item) => event.childIds.contains(item.id))
                            .firstOrNull;
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: child == null
                                  ? Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                  : Color(child.colorArgb),
                              child: const Icon(Icons.event),
                            ),
                            title: Text(event.title),
                            subtitle: Text(
                              _eventSummary(
                                event,
                                item.displayStart,
                                child?.name,
                              ),
                            ),
                            onTap: () => _editEvent(context, event),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'cancel') controller.cancel(event);
                                if (value == 'delete') controller.delete(event);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'cancel',
                                  child: Text('Cancel event'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete event'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );

  List<({CalendarEvent event, DateTime displayStart})> _visibleEvents(
    List<CalendarEvent> events,
  ) {
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final rangeStart = switch (controller.range) {
      CalendarRange.today => dayStart,
      CalendarRange.week => dayStart.subtract(
        Duration(days: dayStart.weekday - DateTime.monday),
      ),
      CalendarRange.month => DateTime(now.year, now.month),
    };
    final rangeEnd = switch (controller.range) {
      CalendarRange.today => rangeStart.add(const Duration(days: 1)),
      CalendarRange.week => rangeStart.add(const Duration(days: 7)),
      CalendarRange.month => DateTime(now.year, now.month + 1),
    };
    final result = <({CalendarEvent event, DateTime displayStart})>[];
    for (final event in events) {
      for (final occurrence in occurrencesBetween(
        event,
        rangeStart.toUtc(),
        rangeEnd.toUtc(),
      )) {
        result.add((event: event, displayStart: occurrence.startsAt));
      }
    }
    result.sort(
      (left, right) => left.displayStart.compareTo(right.displayStart),
    );
    return result;
  }

  String _eventSummary(CalendarEvent event, DateTime start, String? childName) {
    final recurring = event.recurrence == null
        ? ''
        : ' · ${event.recurrence!.frequency.name}';
    final child = childName == null ? '' : ' · $childName';
    final pickup = event.pickupGuardianId == null ? '' : ' · pickup assigned';
    return '${start.month}/${start.day} ${TimeOfDay.fromDateTime(start).format24()}$child$recurring$pickup';
  }

  Future<void> _addChild(BuildContext context) async {
    final name = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a child'),
        content: TextField(
          controller: name,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
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
      controller.addChild(name.text, 0xFF8E6CEF);
    }
  }

  Future<void> _editEvent(BuildContext context, [CalendarEvent? event]) async {
    final family = controller.family!;
    final title = TextEditingController(text: event?.title);
    var start =
        event?.localStart ?? DateTime.now().add(const Duration(hours: 1));
    var recurring = event?.recurrence != null;
    var selectedChildren = {...?event?.childIds};
    var pickup = event?.pickupGuardianId;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(event == null ? 'New event' : 'Edit event'),
          content: SingleChildScrollView(
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

class _EmptyCalendar extends StatelessWidget {
  const _EmptyCalendar();
  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.calendar_month_outlined, size: 48),
        SizedBox(height: 12),
        Text('No events yet'),
      ],
    ),
  );
}

extension on TimeOfDay {
  String format24() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}
