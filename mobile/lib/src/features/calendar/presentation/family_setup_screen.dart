import 'package:flutter/material.dart';

import 'calendar_controller.dart';
import 'child_profile_editor.dart';

class FamilySetupScreen extends StatefulWidget {
  const FamilySetupScreen({super.key, required this.controller});
  final CalendarController controller;
  @override
  State<FamilySetupScreen> createState() => _FamilySetupScreenState();
}

class _FamilySetupScreenState extends State<FamilySetupScreen> {
  final _familyName = TextEditingController();
  final _ownerName = TextEditingController();
  String? _createdFamilyId, _error;
  bool _creating = false;

  void _create({bool skip = false}) {
    if (_creating || _createdFamilyId != null) return;
    if (widget.controller.family != null) {
      setState(
        () => _error = 'A family is already available. Return to the calendar.',
      );
      return;
    }
    final family = skip ? '' : _familyName.text.trim();
    final owner = skip ? '' : _ownerName.text.trim();
    if (family.length > 120 || owner.length > 120) {
      setState(() => _error = 'Use at most 120 characters for each name.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      widget.controller.createFamily(
        family.isEmpty ? 'My family' : family,
        owner.isEmpty ? 'Me' : owner,
      );
      _createdFamilyId = widget.controller.family!.householdId;
      if (skip) {
        Navigator.pop(context);
        return;
      }
      setState(() => _creating = false);
    } catch (_) {
      // Never repeat creation if a callback failed after the local commit.
      setState(() {
        _createdFamilyId = widget.controller.family?.householdId;
        _creating = false;
        _error = _createdFamilyId == null
            ? 'Could not create your family. Please try again.'
            : 'Your family is saved locally. Return to the calendar to finish setup.';
      });
    }
  }

  @override
  void dispose() {
    _familyName.dispose();
    _ownerName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final family = widget.controller.family;
      final created = _createdFamilyId != null;
      final sameFamily = family?.householdId == _createdFamilyId;
      return Scaffold(
        appBar: AppBar(
          title: Text(
            created ? 'Add children (optional)' : 'Set up your family',
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!created) ...[
                const Text(
                  'Add names now, or skip setup and start using your calendar. Children can be added next or later.',
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('setup-family-name'),
                  controller: _familyName,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Family name (optional)',
                    hintText: 'My family',
                  ),
                ),
                TextField(
                  key: const Key('setup-owner-name'),
                  controller: _ownerName,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Your display name (optional)',
                    hintText: 'Me',
                  ),
                ),
                FilledButton(
                  key: const Key('setup-continue'),
                  onPressed: _creating ? null : () => _create(),
                  child: const Text('Continue'),
                ),
                TextButton(
                  key: const Key('setup-skip'),
                  onPressed: _creating ? null : () => _create(skip: true),
                  child: const Text('Skip setup'),
                ),
              ] else ...[
                const Text(
                  'Your calendar is ready. Children are saved as you add them; you can finish now or add more later.',
                ),
                const SizedBox(height: 12),
                if (sameFamily) ...[
                  for (final child in family!.children)
                    ListTile(
                      key: Key('setup-child-${child.id}'),
                      leading: CircleAvatar(
                        backgroundColor: Color(child.colorArgb),
                        child: const Icon(Icons.person_outline),
                      ),
                      title: Text(child.name),
                      subtitle: Text(
                        ChildColours.values
                                .where((c) => c.argb == child.colorArgb)
                                .firstOrNull
                                ?.name ??
                            'Custom colour',
                      ),
                    ),
                  if (widget.controller.canManageFamily)
                    OutlinedButton.icon(
                      key: const Key('setup-add-child'),
                      icon: const Icon(Icons.person_add_alt),
                      label: const Text('Add child'),
                      onPressed: () =>
                          showAddChildProfileDialog(context, widget.controller),
                    ),
                ],
                if (!sameFamily || !widget.controller.canManageFamily)
                  const Text('Family access changed. Return to the calendar.'),
                FilledButton(
                  key: const Key('setup-open-calendar'),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Open calendar'),
                ),
              ],
              if (_error != null) Text(_error!, key: const Key('setup-error')),
            ],
          ),
        ),
      );
    },
  );
}
