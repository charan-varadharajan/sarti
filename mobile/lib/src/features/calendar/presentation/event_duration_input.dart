import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

/// UI hours/minutes, with an unchanged elapsed-minute domain value.
class EventDurationInput extends StatefulWidget {
  const EventDurationInput({
    super.key,
    required this.controller,
    required this.fieldKey,
    required this.onChanged,
    this.helperText,
  });
  final TextEditingController controller;
  final String fieldKey;
  final VoidCallback onChanged;
  final String? helperText;

  @override
  State<EventDurationInput> createState() => _EventDurationInputState();
}

class _EventDurationInputState extends State<EventDurationInput> {
  final _hours = TextEditingController();
  final _minutes = TextEditingController();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _read();
    widget.controller.addListener(_read);
  }

  void _read() {
    if (_editing) return;
    final value = int.tryParse(widget.controller.text);
    _hours.text = value == null ? '' : '${value ~/ 60}';
    _minutes.text = value == null ? '' : '${value % 60}';
  }

  void _write() {
    final hours = int.tryParse(_hours.text.isEmpty ? '0' : _hours.text);
    final minutes = int.tryParse(_minutes.text.isEmpty ? '0' : _minutes.text);
    _editing = true;
    widget.controller.text =
        hours == null ||
            minutes == null ||
            hours < 0 ||
            minutes < 0 ||
            minutes > 59 ||
            (_hours.text.isEmpty && _minutes.text.isEmpty)
        ? ''
        : '${hours * 60 + minutes}';
    _editing = false;
    widget.onChanged();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_read);
    _hours.dispose();
    _minutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Duration'),
      Row(
        children: [
          Expanded(
            child: TextField(
              key: Key('${widget.fieldKey}-hours'),
              controller: _hours,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Hours'),
              onChanged: (_) => _write(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              key: Key(widget.fieldKey),
              controller: _minutes,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Minutes (0–59)'),
              onChanged: (_) => _write(),
            ),
          ),
        ],
      ),
      if (widget.helperText != null)
        Text(widget.helperText!, style: Theme.of(context).textTheme.bodySmall),
      if (int.tryParse(widget.controller.text) == null ||
          (int.tryParse(widget.controller.text) ?? 0) < 1 ||
          (int.tryParse(widget.controller.text) ?? 0) > 10080)
        const Text('Choose a duration from 1 minute to 7 days.'),
    ],
  );
}

/// Include date across midnight and zone across a DST transition.
String formatEventEnd(BuildContext context, tz.TZDateTime start, int minutes) {
  final end = start.add(Duration(minutes: minutes));
  final sameDay =
      start.year == end.year &&
      start.month == end.month &&
      start.day == end.day;
  final time = TimeOfDay.fromDateTime(end).format(context);
  final date = sameDay
      ? ''
      : '${MaterialLocalizations.of(context).formatMediumDate(end)}, ';
  final zone = start.timeZoneOffset == end.timeZoneOffset
      ? ''
      : ' ${end.timeZoneName}';
  return '$date$time$zone';
}
