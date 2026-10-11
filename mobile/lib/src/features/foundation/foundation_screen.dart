import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarti_mobile/src/features/foundation/foundation_providers.dart';

class FoundationScreen extends ConsumerWidget {
  const FoundationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final encryption = ref.watch(localEncryptionStatusProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Sarti')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Your family's wise companion.",
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              encryption.when(
                data: (_) => const _Status(
                  icon: Icons.lock_outline,
                  message: 'Local encryption engine ready',
                ),
                error: (_, _) => const _Status(
                  icon: Icons.error_outline,
                  message: 'Secure local storage is unavailable',
                ),
                loading: () => const CircularProgressIndicator(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon),
          const SizedBox(width: 8),
          Flexible(child: Text(message)),
        ],
      ),
    );
  }
}
