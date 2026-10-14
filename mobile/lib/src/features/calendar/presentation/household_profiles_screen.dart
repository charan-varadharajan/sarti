import 'package:flutter/material.dart';

import '../data/calendar_repository.dart';
import 'calendar_controller.dart';
import 'child_profile_editor.dart';
import 'guardian_management_action.dart';

/// Profile labels/colours are shared separately from appointment visibility.
class HouseholdProfilesScreen extends StatelessWidget {
  const HouseholdProfilesScreen({
    super.key,
    required this.controller,
    this.petsOnly = false,
    this.onGuardians,
  });
  final CalendarController controller;
  final bool petsOnly;
  final VoidCallback? onGuardians;

  Future<int?> _colour(BuildContext context, int? current) => showDialog<int>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Choose color'),
      children: [
        for (final colour in ChildColours.values)
          SimpleDialogOption(
            key: Key('profile-colour-${colour.name.toLowerCase()}'),
            onPressed: () => Navigator.pop(context, colour.argb),
            child: Row(
              children: [
                CircleAvatar(backgroundColor: Color(colour.argb), radius: 12),
                const SizedBox(width: 12),
                Text(colour.name),
                if (colour.argb == current) const Icon(Icons.check),
              ],
            ),
          ),
      ],
    ),
  );

  Future<void> _edit(
    BuildContext context,
    String kind, [
    ParticipantProfile? profile,
  ]) async {
    final name = TextEditingController(text: profile?.name);
    var colour = profile?.colorArgb ?? ChildColours.values.first.argb;
    String? error;
    final route = DialogRoute<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(kind == 'pet' ? 'Pet profile' : 'My adult profile'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const Key('profile-name'),
                  controller: name,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                ListTile(
                  title: const Text('Choose color'),
                  leading: CircleAvatar(backgroundColor: Color(colour)),
                  onTap: () async {
                    final selected = await _colour(context, colour);
                    if (selected != null && context.mounted) {
                      setState(() => colour = selected);
                    }
                  },
                ),
                const Text(
                  'Saving shares this profile name and colour with calendar guardians. Your private appointments stay private.',
                ),
                if (error != null) Text(error!),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('profile-save'),
              onPressed: () {
                try {
                  if (kind == 'pet' && !controller.canManageFamily) {
                    throw StateError('Access changed');
                  }
                  controller.repository.saveParticipant(
                    id: profile?.id,
                    name: name.text,
                    kind: kind,
                    colour: colour,
                  );
                  controller.refresh();
                  controller.onLocalMutation?.call();
                  Navigator.pop(context);
                } catch (_) {
                  setState(
                    () => error = 'Could not save. Check the name and your current access.',
                  );
                }
              },
              child: const Text('Save shared profile'),
            ),
          ],
        ),
      ),
    );
    await Navigator.of(context).push(route);
    await route.completed;
    name.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(petsOnly ? 'Pets' : 'People')),
    body: ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final family = controller.family!;
        final self = family.participants
            .where(
              (p) =>
                  p.kind == 'adult' &&
                  p.adultId == controller.repository.currentAdultId,
            )
            .firstOrNull;
        return ListView(
          children: [
            if (!petsOnly) const ListTile(title: Text('Adults')),
            if (!petsOnly &&
                (controller.repository.currentAdultId != null ||
                    controller.canManageFamily))
              ListTile(
                key: const Key('my-profile'),
                leading: const Icon(Icons.person_outline),
                title: Text(self?.name ?? 'Set up my adult profile'),
                subtitle: const Text(
                  'Name and color; appointments remain private by default',
                ),
                onTap: () => _edit(context, 'adult', self),
              ),
            if (!petsOnly && controller.canManageFamily) ...[
              ListTile(
                key: const Key('add-adult'),
                leading: const Icon(Icons.person_add_alt_1),
                title: const Text('Add adult'),
                subtitle: const Text('Invite an adult to join securely'),
                onTap: () => openGuardianManagement(context, onGuardians),
              ),
              ListTile(
                key: const Key('people-add-child'),
                leading: const Icon(Icons.child_care),
                title: const Text('Add child'),
                onTap: () => showAddChildProfileDialog(context, controller),
              ),
            ],
            if (petsOnly && controller.canManageFamily)
              ListTile(
                key: const Key('add-pet'),
                leading: const Icon(Icons.pets),
                title: const Text('Add pet'),
                onTap: () => _edit(context, 'pet'),
              ),
            if (!petsOnly)
              for (final guardian in family.guardians.where(
                (g) => !family.participants.any(
                  (p) => p.kind == 'adult' && p.adultId == g.id,
                ),
              ))
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(guardian.name),
                  subtitle: const Text('Adult'),
                ),
            if (!petsOnly) const ListTile(title: Text('Children')),
            for (final child in petsOnly ? <ChildProfile>[] : family.children)
              ListTile(
                title: Text(child.name),
                subtitle: const Text('Child'),
                leading: CircleAvatar(
                  backgroundColor: Color(child.colorArgb),
                  child: const Icon(Icons.child_care, color: Colors.black87),
                ),
                onTap: !controller.canManageFamily
                    ? null
                    : () async {
                        final colour = await _colour(context, child.colorArgb);
                        if (colour == null ||
                            !context.mounted ||
                            !controller.canManageFamily) {
                          return;
                        }
                        controller.repository.updateChildColour(
                          child.id,
                          colour,
                        );
                        controller.refresh();
                        controller.onLocalMutation?.call();
                      },
              ),
            for (final profile in family.participants.where(
              (p) =>
                  p != self && (petsOnly ? p.kind == 'pet' : p.kind == 'adult'),
            ))
              ListTile(
                title: Text(profile.name),
                subtitle: Text(profile.kind == 'pet' ? 'Pet' : 'Adult'),
                leading: CircleAvatar(
                  backgroundColor: Color(profile.colorArgb),
                  child: Icon(
                    profile.kind == 'pet' ? Icons.pets : Icons.person,
                    color: Colors.black87,
                  ),
                ),
                onTap: profile.kind == 'pet' && controller.canManageFamily
                    ? () => _edit(context, 'pet', profile)
                    : null,
              ),
          ],
        );
      },
    ),
  );
}
