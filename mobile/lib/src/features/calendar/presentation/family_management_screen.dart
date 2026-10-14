import 'package:flutter/material.dart';

import 'calendar_controller.dart';
import 'household_profiles_screen.dart';
import 'child_profile_editor.dart';
import 'calendar_retention_screen.dart';

class FamilyManagementScreen extends StatelessWidget {
  const FamilyManagementScreen({
    super.key,
    required this.controller,
    this.onGuardians,
  });
  final CalendarController controller;
  final VoidCallback? onGuardians;

  Future<void> _rename(
    BuildContext context,
    String title,
    String value,
    void Function(String) save,
  ) async {
    final text = TextEditingController(text: value);
    String? error;
    final route = DialogRoute<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('family-edit-name'),
                controller: text,
                maxLength: 120,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              if (error != null) Text(error!),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  save(text.text);
                  Navigator.pop(context);
                } catch (_) {
                  setState(
                    () => error =
                        'Check the name and your current family access.',
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    await Navigator.of(context).push(route);
    await route.completed;
    text.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final family = controller.family;
      if (family == null) {
        return const Scaffold(
          body: Center(child: Text('No family available.')),
        );
      }
      final admin = controller.canManageFamily;
      return Scaffold(
        appBar: AppBar(title: const Text('Family')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              title: Text(family.name),
              subtitle: const Text('Family name'),
              trailing: admin ? const Icon(Icons.edit) : null,
              onTap: admin
                  ? () => _rename(
                      context,
                      'Family name',
                      family.name,
                      (name) => controller.saveFamilyDetails(name, {}),
                    )
                  : null,
            ),
            if (!admin)
              const Text(
                'Only a family admin can change family details. You can still manage your own private profile.',
              ),
            const Text('Adults'),
            for (final g in family.guardians)
              ListTile(
                title: Text(g.name),
                trailing: admin ? const Icon(Icons.edit) : null,
                onTap: admin
                    ? () => _rename(
                        context,
                        'Guardian display name',
                        g.name,
                        (name) => controller.saveFamilyDetails(family.name, {
                          g.id: name,
                        }),
                      )
                    : null,
              ),
            ListTile(
              title: const Text('Invite or remove guardians'),
              subtitle: Text(
                onGuardians == null
                    ? 'Connect and sign in to your configured Sarti service. Removal requires current server authorization.'
                    : 'Invitations, device approval and secure removal',
              ),
              enabled: onGuardians != null,
              onTap: onGuardians,
            ),
            const Text('Children'),
            for (final child in family.children)
              ListTile(
                leading: CircleAvatar(backgroundColor: Color(child.colorArgb)),
                title: Text(child.name),
                trailing: admin ? const Icon(Icons.edit) : null,
                onTap: admin
                    ? () => _rename(
                        context,
                        'Child name',
                        child.name,
                        (name) => controller.renameChild(child.id, name),
                      )
                    : null,
              ),
            if (admin)
              OutlinedButton.icon(
                onPressed: () => showAddChildProfileDialog(context, controller),
                icon: const Icon(Icons.person_add),
                label: const Text('Add child'),
              ),
            ListTile(
              title: const Text('People & pets'),
              subtitle: const Text('Adult/pet profiles and pastel colours'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      HouseholdProfilesScreen(controller: controller),
                ),
              ),
            ),
            ListTile(
              title: const Text('Calendar retention'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      CalendarRetentionScreen(controller: controller),
                ),
              ),
            ),
            const Text(
              'Profile edits are encrypted on this phone. Offline changes sync when access and keys are available; they do not change membership permissions.',
            ),
          ],
        ),
      );
    },
  );
}
