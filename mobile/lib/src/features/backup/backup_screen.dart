import 'package:flutter/material.dart';
import 'package:sarti_mobile/src/core/backup/backup_service.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({
    super.key,
    required this.hasBackup,
    required this.canCreate,
    required this.create,
    required this.restore,
    required this.remove,
    required this.generatePhrase,
    this.updatedAt,
    this.personal = false,
  });
  final bool personal;
  final bool hasBackup;
  final bool canCreate;
  final DateTime? updatedAt;
  final String Function() generatePhrase;
  final Future<void> Function(String phrase) create;
  final Future<void> Function(String phrase) restore;
  final Future<void> Function() remove;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final _phrase = TextEditingController();
  bool _busy = false;
  bool _saved = false;
  String? _generated;
  String? _message;
  late bool _hasBackup = widget.hasBackup;
  @override
  void dispose() {
    _phrase.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() operation, String success) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await operation();
      _phrase.clear();
      if (mounted) {
        setState(() {
          _message = success;
          _generated = null;
          _saved = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Could not complete recovery. Check your connection and recovery phrase, then try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.personal ? 'My private backup' : 'Family backup'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          widget.personal
              ? 'Only your account can retrieve this encrypted snapshot. Use a separate recovery phrase for your private appointments; login alone cannot unlock it.'
              : 'Family backups exclude private adult appointments. Your 12-word recovery phrase stays with you. Login alone cannot unlock it.',
        ),
        if (widget.updatedAt != null)
          Text('Latest snapshot: ${widget.updatedAt!.toLocal()}'),
        if (widget.canCreate)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('Create a replacement-phone backup'),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _generated = widget.generatePhrase();
                            _saved = false;
                          }),
                    child: const Text('Generate recovery phrase'),
                  ),
                  if (_generated != null) ...[
                    SelectableText(_generated!),
                    CheckboxListTile(
                      title: const Text(
                        'I saved these 12 words somewhere safe',
                      ),
                      value: _saved,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _saved = v!),
                    ),
                    FilledButton(
                      onPressed: _busy || !_saved
                          ? null
                          : () => _run(() async {
                              await widget.create(_generated!);
                              _hasBackup = true;
                            }, 'Encrypted backup uploaded.'),
                      child: const Text('Encrypt and upload backup'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        if (_hasBackup && !widget.canCreate)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('Restore your family calendar on this phone'),
                  TextField(
                    controller: _phrase,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: '12-word recovery phrase',
                    ),
                  ),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            final phrase = BackupService.validateRecoveryPhrase(
                              _phrase.text,
                            );
                            await widget.restore(phrase);
                          }, 'Backup restored securely.'),
                    child: const Text('Restore backup'),
                  ),
                ],
              ),
            ),
          ),
        if (_hasBackup)
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete server backup?'),
                        content: const Text(
                          'This removes your recovery snapshot. Your local calendar stays on this phone.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Delete backup'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await _run(() async {
                        await widget.remove();
                        _hasBackup = false;
                      }, 'Server backup deleted.');
                    }
                  },
            child: const Text('Delete server backup'),
          ),
        if (_busy) const LinearProgressIndicator(),
        if (_message != null) Text(_message!),
      ],
    ),
  );
}
