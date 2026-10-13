import 'package:flutter/material.dart';

import 'calendar_controller.dart';

class ChildColour {
  const ChildColour(this.name, this.argb);
  final String name;
  final int argb;
}

abstract final class ChildColours {
  static const values = [
    ChildColour('Blue', 0xff1565c0),
    ChildColour('Green', 0xff2e7d32),
    ChildColour('Purple', 0xff6a1b9a),
    ChildColour('Orange', 0xff9a4d00),
    ChildColour('Rose', 0xffad1457),
    ChildColour('Teal', 0xff00695c),
  ];

  static int? firstUnused(Iterable<int> used) {
    final existing = used.toSet();
    return values
        .where((colour) => !existing.contains(colour.argb))
        .firstOrNull
        ?.argb;
  }
}

Future<bool> showAddChildProfileDialog(
  BuildContext context,
  CalendarController controller,
) async {
  final family = controller.family;
  if (family == null || !controller.canManageFamily) return false;
  return await showDialog<bool>(
        context: context,
        builder: (_) => _ChildProfileEditor(
          controller: controller,
          familyId: family.householdId,
        ),
      ) ??
      false;
}

class _ChildProfileEditor extends StatefulWidget {
  const _ChildProfileEditor({required this.controller, required this.familyId});
  final CalendarController controller;
  final String familyId;
  @override
  State<_ChildProfileEditor> createState() => _ChildProfileEditorState();
}

class _ChildProfileEditorState extends State<_ChildProfileEditor> {
  final _name = TextEditingController();
  final _alias = TextEditingController();
  late int? _colour = ChildColours.firstUnused(
    widget.controller.family?.children.map((child) => child.colorArgb) ??
        const [],
  );
  bool _share = false, _saving = false;
  String? _error;

  bool get _allowed =>
      widget.controller.family?.householdId == widget.familyId &&
      widget.controller.canManageFamily;
  bool get _valid =>
      _name.text.trim().isNotEmpty &&
      _name.text.trim().length <= 120 &&
      _colour != null;

  void _add() {
    if (_saving) return;
    if (!_allowed) {
      setState(() => _error = 'Family access changed. Return to the calendar.');
      return;
    }
    if (!_valid) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      widget.controller.addChild(
        _name.text,
        _colour!,
        cloudAlias: _alias.text,
        shareWithCalendarGuardians: _share,
      );
      Navigator.pop(context, true);
    } on ArgumentError {
      setState(() {
        _saving = false;
        _error = 'Check the name and private alias. The alias must be unique and different from the child’s name.';
      });
    } catch (_) {
      setState(() {
        _saving = false;
        _error = 'Could not finish adding the child. Return to the calendar to check before retrying.';
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _alias.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => AlertDialog(
      title: const Text('Add a child'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('child-name'),
            controller: _name,
            autofocus: true,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'Name'),
            onChanged: (_) => setState(() {}),
          ),
          const Text('Calendar colour'),
          Wrap(
            spacing: 6,
            children: [
              for (final colour in ChildColours.values)
                ChoiceChip(
                  key: Key('child-colour-${colour.name.toLowerCase()}'),
                  label: Text(colour.name),
                  avatar: CircleAvatar(
                    radius: 6,
                    backgroundColor: Color(colour.argb),
                  ),
                  selected: _colour == colour.argb,
                  onSelected: _allowed && !_saving
                      ? (_) => setState(() => _colour = colour.argb)
                      : null,
                ),
            ],
          ),
          if (ChildColours.firstUnused(
                widget.controller.family?.children.map((c) => c.colorArgb) ??
                    const [],
              ) ==
              null)
            const Text(
              'All suggested colours are in use. Choose one to reuse; child names remain visible.',
            ),
          TextField(
            key: const Key('child-alias'),
            controller: _alias,
            maxLength: 32,
            decoration: const InputDecoration(
              labelText: 'Private alias (optional)',
              hintText: 'Example: happy-frog-4821',
              helperText: 'Stored encrypted; cloud AI uses temporary labels.',
            ),
          ),
          CheckboxListTile(
            key: const Key('share-child-profile'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Share profile with current calendar guardians'),
            subtitle: const Text(
              'Grants read access when this child first syncs.',
            ),
            value: _share,
            onChanged: _allowed && !_saving
                ? (value) => setState(() => _share = value ?? false)
                : null,
          ),
          if (!_allowed)
            const Text('Family access changed. Return to the calendar.'),
          if (_error != null) Text(_error!, key: const Key('child-error')),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('child-save'),
          onPressed: !_saving && _allowed && _valid ? _add : null,
          child: const Text('Add'),
        ),
      ],
    ),
  );
}
