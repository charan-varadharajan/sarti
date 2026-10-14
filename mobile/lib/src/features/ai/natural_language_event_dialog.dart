import '../calendar/presentation/event_duration_input.dart';

import 'dart:convert';

import 'package:flutter/material.dart';

import 'gemini_ai_provider.dart';
import 'cloud_ai_consent.dart';
import '../../core/network/sarti_api.dart';

import '../../core/ids.dart';

import 'package:sarti_mobile/src/features/ai/event_parser.dart';
import 'package:sarti_mobile/src/features/ai/native_ai_provider.dart';
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/features/calendar/domain/calendar_event.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_controller.dart';
import 'package:timezone/timezone.dart' as tz;

Future<List<CalendarEvent>?> showNaturalLanguageEventDialog(
  BuildContext context, {
  required CalendarController controller,
  required NativeEventAiProvider provider,
  SartiApiClient? cloudApi,
  CloudAiConsentController? cloudConsent,
  String? initialInput,
  String? sourceLabel,
}) => showDialog<List<CalendarEvent>>(
  context: context,
  barrierDismissible: false,
  builder: (context) => _NaturalLanguageEventDialog(
    controller: controller,
    provider: provider,
    cloudApi: cloudApi,
    cloudConsent: cloudConsent,
    initialInput: initialInput,
    sourceLabel: sourceLabel,
  ),
);

class _NaturalLanguageEventDialog extends StatefulWidget {
  const _NaturalLanguageEventDialog({
    required this.controller,
    required this.provider,
    this.cloudApi,
    this.cloudConsent,
    this.initialInput,
    this.sourceLabel,
  });

  final SartiApiClient? cloudApi;
  final CloudAiConsentController? cloudConsent;
  final CalendarController controller;
  final NativeEventAiProvider provider;
  final String? initialInput;
  final String? sourceLabel;

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
  List<EventProposal> _proposals = [];
  final List<CalendarEvent> _drafts = [];
  int _index = 0;
  bool _needsDurationClarification = false;
  final _duration = TextEditingController();
  DateTime? _date;
  ParsedTime? _time;
  Set<String> _childIds = {};
  String? _pickupGuardianId;
  bool _loading = false;

  FamilyCalendar get _family => widget.controller.family!;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialInput?.trim();
    if (initial != null && initial.isNotEmpty) {
      _input.text = initial;
      WidgetsBinding.instance.addPostFrameCallback((_) => _preview());
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _title.dispose();
    _location.dispose();
    _duration.dispose();
    super.dispose();
  }

  Future<void> _preview() async {
    if (_input.text.trim().isEmpty) return;
    setState(() => _loading = true);
    final zone = tz.getLocation(widget.controller.timezone);
    final bases = const DeterministicEventParser().parseAll(
      _input.text.trim(),
      now: tz.TZDateTime.from(widget.controller.clock(), zone),
    );
    final proposals = <EventProposal>[];
    for (final base in bases) {
      proposals.add(await widget.provider.tryEnrich(base));
    }
    if (!mounted) return;
    _proposals = proposals;
    _drafts.clear();
    _index = 0;
    _loadProposal();
  }

  void _loadProposal() {
    final proposal = _proposals[_index];
    _needsDurationClarification = proposal.requiresDurationConfirmation;
    _duration.text = proposal.requiresDurationConfirmation
        ? ''
        : '${proposal.durationMinutes ?? 60}';
    _title.text = proposal.title ?? '';
    _location.text = proposal.location ?? '';
    _date = proposal.date;
    _time = proposal.timeOfDay;
    if (_date != null &&
        _time != null &&
        proposal.endTimeOfDay != null &&
        !proposal.requiresDurationConfirmation) {
      final zone = tz.getLocation(widget.controller.timezone);
      final endClock = proposal.endTimeOfDay!;
      final start = tz.TZDateTime(
        zone,
        _date!.year,
        _date!.month,
        _date!.day,
        _time!.hour,
        _time!.minute,
      );
      var end = tz.TZDateTime(
        zone,
        _date!.year,
        _date!.month,
        _date!.day,
        endClock.hour,
        endClock.minute,
      );
      if (!end.isAfter(start)) {
        end = tz.TZDateTime(
          zone,
          _date!.year,
          _date!.month,
          _date!.day + 1,
          endClock.hour,
          endClock.minute,
        );
      }
      final elapsed = end.difference(start).inMinutes;
      if (proposal.hasExplicitDuration && proposal.durationMinutes != elapsed) {
        _duration.text = '';
        _needsDurationClarification = true;
      } else {
        _duration.text = '$elapsed';
      }
    }

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

  Future<void> _cloudAssist() async {
    if (_loading ||
        _proposal == null ||
        widget.cloudApi == null ||
        widget.cloudConsent?.enabled != true) {
      return;
    }
    setState(() => _loading = true);
    try {
      final capability = await widget.cloudApi!.cloudCapability();
      if (capability['available'] != true ||
          capability['consent_version'] != 3 ||
          widget.cloudConsent?.enabled != true) {
        if (mounted) {
          setState(
            () => _saveError = 'Cloud assistance is unavailable. Continue with the local preview.',
          );
        }
        return;
      }
      final gate = CloudAiGate(
        consent: widget.cloudConsent!,
        available: true,
        providerFactory: () => GeminiAiProvider.broker((payload) async {
          if (widget.cloudConsent?.enabled != true) return null;
          return jsonEncode(
            await widget.cloudApi!.cloudProposal(
              Map<String, dynamic>.from(jsonDecode(payload) as Map),
            ),
          );
        }),
      );
      final provider = gate.createProvider();
      if (provider == null) return;
      final enriched = await provider.tryEnrich(
        _proposal!,
        childAliases: {for (final c in _family.children) c.name: c.cloudAlias},
        guardianNames: _family.guardians.map((g) => g.name),
      );
      if (!mounted || widget.cloudConsent?.enabled != true) return;
      setState(() {
        if (identical(enriched, _proposal)) {
          _saveError = 'Cloud assist added no verified information. Continue with the local preview.';
        }
        _proposal = enriched;
        _time ??= enriched.timeOfDay;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _saveError = 'Cloud assistance is unavailable. Continue locally.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
    final duration = int.tryParse(_duration.text);
    if (duration == null || duration < 1 || duration > 10080) return;
    _drafts.add(
      CalendarEvent(
        id: newId(),
        householdId: _family.householdId,
        calendarResourceId: _family.calendarResourceId,
        title: _title.text.trim(),
        notes: _location.text.trim().isEmpty
            ? null
            : 'Location: ${_location.text.trim()}',
        localStart: start,
        timezone: widget.controller.timezone,
        durationMinutes: duration,
        childIds: _childIds.toList(),
        pickupGuardianId: _pickupGuardianId,
        recurrence: _proposal?.toRecurrenceRule(),
        reminderMinutes: const [30],
        revision: 1,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    if (_index + 1 < _proposals.length) {
      _index++;
      _loadProposal();
      return;
    }
    try {
      widget.controller.saveReviewedEvents(_drafts);
      Navigator.pop(context, List<CalendarEvent>.of(_drafts));
    } catch (_) {
      _drafts.removeLast();
      setState(
        () => _saveError =
            'Could not save. Review your details and current calendar access.',
      );
    }
  }

  String? _saveError;
  bool get _validDuration {
    final v = int.tryParse(_duration.text);
    return v != null && v > 0 && v <= 10080;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      _proposal == null
          ? 'Describe an event'
          : _proposals.length == 1
          ? 'Review suggestion'
          : 'Review suggestion ${_index + 1} of ${_proposals.length}',
    ),
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
              _title.text.trim().isNotEmpty &&
                  _date != null &&
                  !_loading &&
                  _time != null &&
                  _validDuration
              ? _save
              : null,
          child: Text(
            _index + 1 < _proposals.length
                ? 'Review next'
                : _proposals.length == 1
                ? 'Add to calendar'
                : 'Add ${_proposals.length} to calendar',
          ),
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
      if (widget.sourceLabel case final source?)
        Align(
          alignment: Alignment.centerLeft,
          child: Text(source, style: Theme.of(context).textTheme.bodySmall),
        ),
      if (widget.cloudApi != null && widget.cloudConsent?.enabled == true)
        OutlinedButton(
          onPressed: _loading ? null : _cloudAssist,
          child: const Text('Use cloud assist'),
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
      EventDurationInput(
        controller: _duration,
        fieldKey: 'proposal-duration',
        onChanged: () => setState(() {}),
        helperText: _needsDurationClarification
            ? 'Conflicting or invalid duration — choose before saving'
            : _proposal!.durationMinutes == null
            ? (_duration.text == '60' ? 'Default: 1 hour' : 'Edited duration')
            : 'Duration from your description',
      ),
      if (_date != null && _time != null && _validDuration)
        Text('Ends: ${_endPreview()}'),
      if (_saveError != null) Text(_saveError!),
      if (_proposal!.requiresTimeConfirmation && _time == null)
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Is that AM or PM? Choose the intended time before adding it.',
          ),
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

  String _endPreview() {
    final start = tz.TZDateTime(
      tz.getLocation(widget.controller.timezone),
      _date!.year,
      _date!.month,
      _date!.day,
      _time!.hour,
      _time!.minute,
    );
    return formatEventEnd(context, start, int.parse(_duration.text));
  }

  String _recurrenceSummary(EventProposal proposal) {
    final frequency = proposal.recurrenceFrequency!.name;
    final weekday = proposal.recurrenceWeekday;
    return weekday == null ? frequency : '$frequency · weekday $weekday';
  }
}
