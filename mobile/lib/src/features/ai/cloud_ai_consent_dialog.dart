import 'package:flutter/material.dart';
import 'package:sarti_mobile/src/features/ai/cloud_ai_consent.dart';

Future<void> showCloudAiConsentDialog(
  BuildContext context,
  CloudAiConsentController controller,
) => showDialog<void>(
  context: context,
  builder: (context) => _CloudAiConsentDialog(controller: controller),
);

class _CloudAiConsentDialog extends StatelessWidget {
  const _CloudAiConsentDialog({required this.controller});

  final CloudAiConsentController controller;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Privacy & AI'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sarti can optionally use Google Gemini to improve uncertain '
            'calendar suggestions.',
          ),
          const SizedBox(height: 12),
          const Text(
            'When configured and enabled, Sarti sends limited scheduling '
            'tokens to Gemini, using fresh temporary labels for known people '
            'and places. Your saved aliases and account IDs are excluded. '
            'Unsupported text stays local. Schedules can still be sensitive '
            'or identifying, and network/provider metadata may link requests. '
            'This is pseudonymization, not anonymization. It does not guarantee '
            'that personal information never leaves your phone.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Cloud AI is optional. The local deterministic parser continues '
            'to work when this is off. Calendar changes always require your '
            'review and approval.',
          ),
          const SizedBox(height: 16),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Allow limited scheduling information to be sent to Gemini',
              ),
              subtitle: Text(
                controller.enabled
                    ? 'Enabled on this device'
                    : 'Off by default',
              ),
              value: controller.enabled,
              onChanged: controller.setEnabled,
            ),
          ),
        ],
      ),
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    ],
  );
}
