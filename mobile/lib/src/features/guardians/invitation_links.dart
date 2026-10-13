import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

final _tokenPattern = RegExp(r'^[A-Za-z0-9_-]{43}$');

String invitationToken(String input) {
  if (input.length > 256) {
    throw const FormatException('Enter a valid Sarti invitation.');
  }
  final value = input.trim();
  if (_tokenPattern.hasMatch(value)) return value;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'sarti' ||
      uri.host != 'invite' ||
      uri.path.isNotEmpty ||
      uri.hasQuery ||
      uri.hasPort ||
      uri.userInfo.isNotEmpty ||
      !_tokenPattern.hasMatch(uri.fragment)) {
    throw const FormatException('Enter a valid Sarti invitation.');
  }
  return uri.fragment;
}

String invitationLink(String token) =>
    'sarti://invite#${invitationToken(token)}';

String guardianKeyDigest(Uint8List signing, Uint8List encryption) {
  if (signing.length != 32 || encryption.length != 32) {
    throw StateError('Invalid device public keys.');
  }
  return sha256.convert([...signing, ...encryption]).toString();
}

String guardianVerificationCode(String digest) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
    throw StateError('Invalid public-key digest.');
  }
  final short = digest.substring(0, 16).toUpperCase();
  return [for (var i = 0; i < 16; i += 4) short.substring(i, i + 4)].join(' ');
}

/// Memory-only inbox; tokens never enter navigation URLs, logs or storage.
class InvitationLinks {
  static final token = ValueNotifier<String?>(null);
  static StreamSubscription<Uri>? _subscription;
  static void start() {
    if (_subscription != null) return;
    final links = AppLinks();
    _subscription = links.uriLinkStream.listen(
      (uri) {
        try {
          token.value = invitationToken(uri.toString());
        } on FormatException {
          /* Ignore unrelated/untrusted links. */
        }
      },
      onError: (Object _) {
        /* Never log incoming URLs. */
      },
    );
  }
}
