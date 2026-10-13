import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarti_mobile/src/app/sarti_app.dart';
import 'package:sarti_mobile/src/features/guardians/invitation_links.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  InvitationLinks.start();
  runApp(const ProviderScope(child: SartiApp()));
}
