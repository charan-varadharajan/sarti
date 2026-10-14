import 'package:flutter/material.dart';

/// Offline profiles never substitute for authenticated guardian membership.
Future<void> openGuardianManagement(
  BuildContext context,
  VoidCallback? onGuardians,
) async {
  if (onGuardians != null) {
    onGuardians();
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Connect to invite adults'),
      content: const Text(
        'This installation is using an offline calendar. Guardian invitations and removal need a configured Sarti service and passkey sign-in. You can keep using this calendar locally. Ask your app administrator for a connected build.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
