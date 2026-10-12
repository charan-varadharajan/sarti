import 'package:flutter/material.dart';
import 'package:sarti_mobile/src/features/ai/event_parser.dart';
import 'package:sarti_mobile/src/features/ai/native_ai_provider.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/features/calendar/domain/calendar_event.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_controller.dart';
import 'package:timezone/timezone.dart' as tz;

Future<CalendarEvent?> showNaturalLanguageEventDialog(
  BuildContext context, {
  required CalendarController controller,
  required NativeEventAiProvider provider,
}) => showDialog<CalendarEvent>(
  context: context,
  barrierDismissible: false,
  builder: (context) =>
      _NaturalLanguageEventDialog(controller: controller, provider: provider),
);

class _NaturalLanguageEventDialog extends StatefulWidget {
  const _NaturalLanguageEventDialog({
    required this.controller,
    required this.provider,
  });

  final CalendarController controller;
  final NativeEventAiProvider provider;

  @override
  State<_NaturalLanguageEventDialog> createState() =>
      _NaturalLanguageEventDialogState();
}

class _NaturalLanguageEventDialogState
    extends State<_NaturalLanguageEventDialog> {
  final _input = TextEditingController();
  final _title = TextEditingController();
  final _location = TextEditingController();
  EventProposal? _proposal;
  DateTime? _date;
  ParsedTime? _time;
  Set<String> _childIds = {};
  String? _pickupGuardianId;
  bool _loading = false;

  FamilyCalendar get _family => widget.controller.family!;

  @override
  void dispose() {
    _input.dispose();
    _title.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _preview() async {
    if (_input.text.trim().isEmpty) return;
    setState(() => _loading = true);
    final zone = tz.getLocation(widget.controller.timezone);
    final base = widget.provider.parse(
      _input.text.trim(),
      now: tz.TZDateTime.now(zone),
    );
    final proposal = await widget.provider.tryEnrich(base);
    if (!mounted) return;
    _title.text = proposal.title ?? '';
    _location.text = proposal.location ?? '';
    _date = proposal.date;
    _time = proposal.timeOfDay;
    _childIds = {
      for (final child in _family.children)
        if (proposal.childNameTokens.any(
          (token) => token.toLowerCase() == child.name.toLowerCase(),
        ))
          child.id,
    };
    _pickupGuardianId = _family.guardians
        .where(
          (guardian) => proposal.guardianNameTokens.any(
            (token) => token.toLowerCase() == guardian.name.toLowerCase(),
          ),
        )
        .firstOrNull
        ?.id;
    setState(() {
      _proposal = proposal;
      _loading = false;
    });
  }

  Future<void> _chooseDate() async {
    final now = DateTime.now();
    final value = await showDatePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 3650)),
      initialDate: _date ?? now,
    );
    if (value != null) setState(() => _date = value);
  }

  Future<void> _chooseTime() async {
    final value = await showTimePicker(
      context: context,
      initialTime: _time == null
          ? TimeOfDay.now()
          : TimeOfDay(hour: _time!.hour, minute: _time!.minute),
    );
    if (value != null) {
      setState(() => _time = ParsedTime(value.hour, value.minute));
    }
  }

  void _save() {
    if (_title.text.trim().isEmpty || _date == null || _time == null) return;
    final start = DateTime(
      _date!.year,
      _date!.month,
      _date!.day,
      _time!.hour,
      _time!.minute,
    );
    final saved = widget.controller.save(
      title: _title.text.trim(),
      notes: _location.text.trim().isEmpty
          ? null
          : 'Location: ${_location.text.trim()}',
      localStart: start,
      durationMinutes: 60,
      childIds: _childIds.toList(),
      pickupGuardianId: _pickupGuardianId,
      recurrence: _proposal?.toRecurrenceRule(),
      reminderMinutes: const [30],
    );
    Navigator.pop(context, saved);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_proposal == null ? 'Describe an event' : 'Review suggestion'),
    content: SingleChildScrollView(
      child: _proposal == null ? _buildInput() : _buildReview(),
    ),
    actions: [
      TextButton(
        onPressed: _loading ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      if (_proposal == null)
        FilledButton(
          onPressed: _loading || _input.text.trim().isEmpty ? null : _preview,
          child: const Text('Preview'),
        )
      else
        FilledButton(
          onPressed:
              _title.text.trim().isNotEmpty && _date != null && _time != null
              ? _save
              : null,
          child: const Text('Add to calendar'),
        ),
    ],
  );

  Widget _buildInput() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextField(
        controller: _input,
        autofocus: true,
        maxLines: 3,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          labelText: 'Event description',
          hintText: 'Mia has swimming every Tuesday at 5 PM',
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        'Sarti uses on-device AI when available and otherwise uses its local parser.',
      ),
      if (_loading) ...[
        const SizedBox(height: 16),
        const Center(child: CircularProgressIndicator()),
      ],
    ],
  );

  Widget _buildReview() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Align(
        alignment: Alignment.centerLeft,
        child: Text('Nothing is saved until you approve this suggestion.'),
      ),
      TextField(
        controller: _title,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(labelText: 'Title'),
      ),
      TextField(
        controller: _location,
        decoration: const InputDecoration(labelText: 'Location (optional)'),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Date'),
        subtitle: Text(
          _date == null
              ? 'Missing — choose a date'
              : '${_date!.year}-${_date!.month.toString().padLeft(2, '0')}-${_date!.day.toString().padLeft(2, '0')}',
        ),
        onTap: _chooseDate,
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Time'),
        subtitle: Text(_time?.toString() ?? 'Missing — choose a time'),
        onTap: _chooseTime,
      ),
      if (_proposal!.recurrenceFrequency != null)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Repeats'),
          subtitle: Text(_recurrenceSummary(_proposal!)),
        ),
      for (final child in _family.children)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(child.name),
          value: _childIds.contains(child.id),
          onChanged: (selected) => setState(() {
            selected == true
                ? _childIds.add(child.id)
                : _childIds.remove(child.id);
          }),
        ),
      DropdownButtonFormField<String?>(
        initialValue: _pickupGuardianId,
        decoration: const InputDecoration(labelText: 'Pickup guardian'),
        items: [
          const DropdownMenuItem(value: null, child: Text('Unassigned')),
          ..._family.guardians.map(
            (guardian) => DropdownMenuItem(
              value: guardian.id,
              child: Text(guardian.name),
            ),
          ),
        ],
        onChanged: (value) => _pickupGuardianId = value,
      ),
    ],
  );

  String _recurrenceSummary(EventProposal proposal) {
    final frequency = proposal.recurrenceFrequency!.name;
    final weekday = proposal.recurrenceWeekday;
    return weekday == null ? frequency : '$frequency · weekday $weekday';
  }
}
