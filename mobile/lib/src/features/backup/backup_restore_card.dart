import 'dart:typed_data';

import 'package:flutter/material.dart';

class BackupRestoreCard extends StatefulWidget {
  const BackupRestoreCard({
    required this.restore,
    required this.storeDatabaseKey,
    super.key,
  });

  final Future<Uint8List> Function(String phrase) restore;
  final Future<void> Function(Uint8List key) storeDatabaseKey;

  @override
  State<BackupRestoreCard> createState() => _BackupRestoreCardState();
}

class _BackupRestoreCardState extends State<BackupRestoreCard> {
  final _phrase = TextEditingController();
  String? _status;
  bool _busy = false;

  @override
  void dispose() {
    _phrase.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final key = await widget.restore(_phrase.text);
      await widget.storeDatabaseKey(key);
      if (mounted) {
        setState(() => _status = 'Backup restored securely.');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _status = 'Could not restore this backup. Check the recovery phrase and file.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Restore encrypted backup',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _phrase,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: '12-word recovery phrase',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _restore,
            child: Text(_busy ? 'Restoring…' : 'Restore backup'),
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_status!),
            ),
        ],
      ),
    ),
  );
}
