import 'dart:convert';

import '../../core/ids.dart';

import 'package:flutter/foundation.dart';
import 'package:sarti_mobile/src/core/crypto/device_key_store.dart';
import 'package:sarti_mobile/src/core/network/sarti_api.dart';
import 'package:sodium/sodium.dart';

class EmailSuggestion {
  const EmailSuggestion({
    required this.familyId,
    required this.id,
    required this.sender,
    required this.subject,
    required this.body,
    required this.receivedAt,
  });

  final String familyId, id;
  final String sender;
  final String subject;
  final String body;
  final DateTime receivedAt;

  String get interpretationInput => [
    if (subject.trim().isNotEmpty) subject.trim(),
    if (body.trim().isNotEmpty) body.trim(),
  ].join('\n');
}

class EmailSuggestionInbox extends ChangeNotifier {
  factory EmailSuggestionInbox({
    required Sodium sodium,
    required DeviceKeyMaterial keys,
    required Future<List<EncryptedEmailDelivery>> Function() fetch,
    required Future<void> Function(String suggestionId) dismissRemote,
  }) => EmailSuggestionInbox._(sodium, keys, fetch, dismissRemote);

  EmailSuggestionInbox._(
    this._sodium,
    this._keys,
    this._fetch,
    this._dismissRemote,
  );

  final Sodium _sodium;
  final DeviceKeyMaterial _keys;
  final Future<List<EncryptedEmailDelivery>> Function() _fetch;
  final Future<void> Function(String suggestionId) _dismissRemote;
  List<EmailSuggestion> suggestions = const [];
  List<EmailSuggestion> forHousehold(String id) =>
      suggestions.where((s) => s.familyId == id).toList();
  bool unavailable = false;

  Future<void> refresh() async {
    try {
      final deliveries = await _fetch();
      final decoded = <EmailSuggestion>[];
      for (final delivery in deliveries) {
        final suggestion = _decrypt(delivery);
        if (suggestion != null) decoded.add(suggestion);
      }
      suggestions = List.unmodifiable(decoded);
      unavailable = false;
      notifyListeners();
    } catch (_) {
      unavailable = true;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> dismiss(String id) async {
    await _dismissRemote(id);
    suggestions = List.unmodifiable(
      suggestions.where((suggestion) => suggestion.id != id),
    );
    notifyListeners();
  }

  EmailSuggestion? _decrypt(EncryptedEmailDelivery delivery) {
    try {
      if (delivery.ciphertext.length > 110000) return null;
      final plaintext = _sodium.crypto.box.sealOpen(
        cipherText: delivery.ciphertext,
        publicKey: _keys.encryptionPublicKey,
        secretKey: _keys.encryptionSecretKey,
      );
      final value = Map<String, Object?>.from(
        jsonDecode(utf8.decode(plaintext)) as Map,
      );
      if (value['version'] != 2 ||
          !isResourceId(delivery.familyId) ||
          value['family_id'] != delivery.familyId ||
          value['suggestion_id'] != delivery.suggestionId) {
        return null;
      }
      final sender = value['sender'];
      final subject = value['subject'];
      final body = value['body'];
      if (sender is! String || subject is! String || body is! String) {
        return null;
      }
      if (sender.length > 320 || subject.length > 998 || body.length > 102400) {
        return null;
      }
      return EmailSuggestion(
        familyId: delivery.familyId,
        id: delivery.suggestionId,
        sender: sender,
        subject: subject,
        body: body,
        receivedAt: delivery.receivedAt,
      );
    } catch (_) {
      return null;
    }
  }
}
