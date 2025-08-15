import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AuthService {
  final GoogleSignIn _google = GoogleSignIn(scopes: ['email', 'profile']);

  Future<String?> signInWithGoogleIdToken() async {
    final acc = await _google.signIn();
    if (acc == null) return null;
    final auth = await acc.authentication;
    // Prefer idToken for backend verification
    return auth.idToken;
  }

  Future<({String? idToken, String? authCode})?> signInWithApple() async {
    if (!Platform.isIOS && !Platform.isMacOS) {
      throw UnsupportedError('Apple Sign-In is only available on Apple platforms.');
    }
    final res = await SignInWithApple.getAppleIDCredential(
      scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
    );
    // Depending on configuration you might get identityToken or authorizationCode
    return (idToken: res.identityToken, authCode: res.authorizationCode);
  }
}
