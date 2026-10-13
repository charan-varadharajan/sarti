import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kalender/kalender.dart' as k;
import 'package:sarti_mobile/src/features/calendar/data/calendar_repository.dart';
import 'package:sarti_mobile/src/features/calendar/domain/calendar_event.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_controller.dart';
import 'package:sarti_mobile/src/features/calendar/presentation/calendar_occurrence_adapter.dart';
import 'package:timezone/timezone.dart' as tz;

/// Kalender owns layout only; callbacks open Sarti's existing explicit editor.
class FamilyCalendarView extends StatefulWidget {
  const FamilyCalendarView({
    super.key,
    required this.family,
    required this.range,
    required this.timezone,
    required this.onEdit,
    required this.onCancel,
    required this.onDelete,
    this.initialDate,
  });

  final FamilyCalendar family;
  final CalendarRange range;
  final String timezone;
  final ValueChanged<CalendarEvent> onEdit;
  final ValueChanged<CalendarEvent> onCancel;
  final ValueChanged<CalendarEvent> onDelete;
  final DateTime? initialDate;

  @override
  State<FamilyCalendarView> createState() => _FamilyCalendarViewState();
}

class _FamilyCalendarViewState extends State<FamilyCalendarView> {
  late final k.DefaultEventsController _events;
  late final k.KalenderController _calendar;
  late DateTime _selectedDay;
  bool _agenda = false;
  List<CalendarDisplayOccurrence> _occurrences = [];

  tz.Location get _location => tz.getLocation(widget.timezone);

  @override
  void initState() {
    super.initState();
    _selectedDay = widget.initialDate ?? tz.TZDateTime.now(_location);
    _events = k.DefaultEventsController(locations: [_location]);
    _calendar = k.KalenderController(
      viewConfiguration: _configuration(),
      location: _location,
    );
    _reload();
  }

  k.ViewConfiguration _configuration() => switch (widget.range) {
    CalendarRange.today => k.MultiDayViewConfiguration.singleDay(
      initialDateTime: _selectedDay,
      initialTimeOfDay: const k.KalenderTime(hour: 6, minute: 0),
      initialHeightPerMinute: 1.2,
    ),
    CalendarRange.week => k.MultiDayViewConfiguration.week(
      initialDateTime: _selectedDay,
      firstDayOfWeek: DateTime.monday,
      initialTimeOfDay: const k.KalenderTime(hour: 6, minute: 0),
      initialHeightPerMinute: 1.2,
    ),
    CalendarRange.month => k.MonthViewConfiguration.singleMonth(
      initialDateTime: _selectedDay,
      firstDayOfWeek: DateTime.monday,
    ),
  };

  @override
  void didUpdateWidget(covariant FamilyCalendarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.timezone != widget.timezone) {
      _calendar.location = _location;
    }
    if (oldWidget.range != widget.range) {
      _calendar.viewConfiguration = _configuration();
      _calendar.jumpToDate(_selectedDay);
    }
    _reload();
  }

  void _reload() {
    final range = _calendar.visibleDateTimeRange.value;
    _occurrences = calendarDisplayOccurrences(
      widget.family,
      range.start,
      range.end,
    );
    _events.replaceEvents(_occurrences);
  }

  void _pageChanged(k.KalenderDateTimeRange range) {
    // Package page callbacks can occur during layout; defer our UI update.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        final day = tz.TZDateTime.from(range.start, _location);
        if (widget.range == CalendarRange.month) {
          final month = tz.TZDateTime(
            _location,
            day.year,
            day.month,
            day.day + 14,
          );
          if (_selectedDay.year != month.year ||
              _selectedDay.month != month.month) {
            _selectedDay = tz.TZDateTime(_location, month.year, month.month);
          }
        } else if (_selectedDay.isBefore(range.start) ||
            !_selectedDay.isBefore(range.end)) {
          _selectedDay = day;
        }
        _reload();
      });
    });
  }

  void _navigate(int direction) {
    final day = tz.TZDateTime.from(_selectedDay, _location);
    final target = switch (widget.range) {
      CalendarRange.today => tz.TZDateTime(
        _location,
        day.year,
        day.month,
        day.day + direction,
      ),
      CalendarRange.week => tz.TZDateTime(
        _location,
        day.year,
        day.month,
        day.day + 7 * direction,
      ),
      CalendarRange.month => tz.TZDateTime(
        _location,
        day.year,
        day.month + direction,
      ),
    };
    setState(() {
      _selectedDay = target;
      _calendar.jumpToDate(target);
      _reload();
    });
  }

  void _today() {
    setState(() {
      _selectedDay = tz.TZDateTime.now(_location);
      _calendar.jumpToDate(_selectedDay);
      _reload();
    });
  }

  @override
  void dispose() {
    _calendar.dispose();
    _events.dispose();
    super.dispose();
  }

  String get _periodLabel {
    final localizations = MaterialLocalizations.of(context);
    if (widget.range == CalendarRange.month) {
      return localizations.formatMonthYear(_selectedDay);
    }
    if (widget.range == CalendarRange.week) {
      final range = _calendar.visibleDateTimeRange.value;
      final start = tz.TZDateTime.from(range.start, _location);
      final end = tz.TZDateTime.from(
        range.end.subtract(const Duration(microseconds: 1)),
        _location,
      );
      return '${localizations.formatShortDate(start)}–${localizations.formatShortDate(end)}';
    }
    return localizations.formatFullDate(_selectedDay);
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          IconButton(
            tooltip: 'Previous period',
            onPressed: () => _navigate(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              _periodLabel,
              key: const Key('calendar-period'),
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
          ),
          IconButton(
            tooltip: 'Next period',
            onPressed: () => _navigate(1),
            icon: const Icon(Icons.chevron_right),
          ),
          IconButton(
            tooltip: 'Go to today',
            onPressed: _today,
            icon: const Icon(Icons.today),
          ),
          IconButton(
            tooltip: _agenda ? 'Show calendar grid' : 'Show agenda',
            onPressed: () => setState(() => _agenda = !_agenda),
            icon: Icon(
              _agenda ? Icons.calendar_view_week : Icons.view_agenda_outlined,
            ),
          ),
        ],
      ),
      Expanded(child: _agenda ? _agendaList(_occurrences) : _grid()),
      if (!_agenda && widget.range == CalendarRange.month)
        SizedBox(
          height: 160,
          child: _agendaList(
            _occurrences.where((event) {
              final start = tz.TZDateTime(
                _location,
                _selectedDay.year,
                _selectedDay.month,
                _selectedDay.day,
              );
              final end = tz.TZDateTime(
                _location,
                start.year,
                start.month,
                start.day + 1,
              );
              return event.start.isBefore(end) && event.end.isAfter(start);
            }).toList(),
            selectedDay: true,
          ),
        ),
    ],
  );

  Widget _grid() => LayoutBuilder(
    builder: (context, constraints) {
      final grid = k.KalenderView(
        key: ValueKey('calendar-grid-${widget.range.name}'),
        eventsController: _events,
        kalenderController: _calendar,
        interaction: k.KalenderInteraction(
          allowEventCreation: false,
          allowRescheduling: false,
          allowResizing: false,
        ),
        callbacks: k.KalenderCallbacks(
          onPageChanged: _pageChanged,
          dateLabel: k.GestureCallbacks<k.DayDetail>(
            onTap: (detail) {
              if (widget.range == CalendarRange.month) {
                setState(
                  () =>
                      _selectedDay = tz.TZDateTime.from(detail.date, _location),
                );
              }
            },
          ),
          onEventTapped: (event) =>
              widget.onEdit((event as CalendarDisplayOccurrence).event),
          onTapped: (date) {
            if (widget.range == CalendarRange.month) {
              setState(
                () => _selectedDay = tz.TZDateTime.from(date, _location),
              );
            }
          },
        ),
        views: [
          k.MultiDayViewParts(
            body: k.MultiDayBody(
              tileComponents: k.TileComponents(tileBuilder: _tile),
            ),
          ),
          k.MonthViewParts(
            body: k.MonthBody(
              tileComponents: k.TileComponents(tileBuilder: _tile),
            ),
          ),
        ],
      );
      if (widget.range != CalendarRange.week) return grid;
      // Keep all seven columns readable on a phone; the agenda needs no sideways scroll.
      return SingleChildScrollView(
        key: const Key('calendar-week-scroll'),
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: math.max(constraints.maxWidth, 840),
          height: constraints.maxHeight,
          child: grid,
        ),
      );
    },
  );

  List<ChildProfile> _children(CalendarEvent event) => widget.family.children
      .where((child) => event.childIds.contains(child.id))
      .toList();

  String _description(CalendarDisplayOccurrence occurrence) {
    final event = occurrence.event;
    final names = _children(event).map((child) => child.name).join(', ');
    final recurrence = event.recurrence == null
        ? ''
        : ' · ${event.recurrence!.frequency.name}';
    final pickup = event.pickupGuardianId == null ? '' : ' · pickup assigned';
    return '${occurrenceTimeLabel(occurrence, widget.timezone)}${names.isEmpty ? '' : ' · $names'}$recurrence$pickup';
  }

  Widget _tile(
    BuildContext context,
    k.KalenderEvent value,
    k.KalenderDateTimeRange range,
  ) {
    final occurrence = value as CalendarDisplayOccurrence;
    final children = _children(occurrence.event);
    final color = children.isEmpty
        ? Theme.of(context).colorScheme.primary
        : Color(children.first.colorArgb);
    return Semantics(
      label: '${occurrence.event.title}, ${_description(occurrence)}',
      button: true,
      child: Tooltip(
        message: '${occurrence.event.title}\n${_description(occurrence)}',
        child: DecoratedBox(
          key: ValueKey('calendar-occurrence-${occurrence.id}'),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            border: Border(left: BorderSide(color: color, width: 4)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: LayoutBuilder(
              builder: (context, constraints) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: Text(
                      occurrence.event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (constraints.maxHeight > 45)
                    Flexible(
                      child: Text(
                        _description(occurrence),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  if (constraints.maxHeight > 60 && children.isNotEmpty)
                    Wrap(
                      spacing: 2,
                      children: children
                          .map(
                            (child) => CircleAvatar(
                              radius: 7,
                              backgroundColor: Color(child.colorArgb),
                              child: Text(
                                child.name.characters.first,
                                style: const TextStyle(fontSize: 9),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _agendaList(
    List<CalendarDisplayOccurrence> occurrences, {
    bool selectedDay = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (selectedDay)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            MaterialLocalizations.of(context).formatFullDate(_selectedDay),
          ),
        ),
      Expanded(
        child: occurrences.isEmpty
            ? const Center(child: Text('No events yet'))
            : ListView.builder(
                key: const Key('calendar-agenda'),
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: occurrences.length,
                itemBuilder: (context, index) {
                  final occurrence = occurrences[index];
                  final children = _children(occurrence.event);
                  final date = tz.TZDateTime.from(occurrence.start, _location);
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: children.isEmpty
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Color(children.first.colorArgb),
                      child: const Icon(Icons.event),
                    ),
                    title: Text(occurrence.event.title),
                    subtitle: Text(
                      '${date.month}/${date.day} ${_description(occurrence)}',
                    ),
                    onTap: () => widget.onEdit(occurrence.event),
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) => action == 'delete'
                          ? widget.onDelete(occurrence.event)
                          : widget.onCancel(occurrence.event),
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
                  );
                },
              ),
      ),
    ],
  );
}
