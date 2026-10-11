import 'package:passkeys/authenticator.dart';
import 'package:passkeys/types.dart';

class NativePasskeyAdapter {
  NativePasskeyAdapter([PasskeyAuthenticator? authenticator])
    : _authenticator = authenticator ?? PasskeyAuthenticator();

  final PasskeyAuthenticator _authenticator;

  Future<Map<String, dynamic>> register(Map<String, dynamic> publicKey) async {
    final request = RegisterRequestType.fromJson(publicKey);
    return (await _authenticator.register(request)).toJson();
  }

  Future<Map<String, dynamic>> authenticate(
    Map<String, dynamic> publicKey,
  ) async {
    final request = AuthenticateRequestType.fromJson(publicKey);
    return (await _authenticator.authenticate(request)).toJson();
  }
}
