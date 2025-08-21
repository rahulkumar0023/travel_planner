import 'dart:convert';
import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AuthService {
  AuthService({required this.baseUrl});

  final String baseUrl;
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

  // 👇 NEW: exchange ID token -> API JWT and persist
  Future<void> exchangeAndStoreToken({
    required String provider, // 'google' | 'apple'
    required String idToken,
  }) async {
    final url = Uri.parse('$baseUrl/auth/exchange');
    final res = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'provider': provider, 'idToken': idToken}),
    );
    if (res.statusCode != 200) {
      throw Exception('Auth exchange failed: ${res.statusCode} ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final p = await SharedPreferences.getInstance();
    await p.setString('api_jwt', data['token'] as String);
    await p.setString('user_email', data['email'] as String? ?? '');
  }
}
