// 👇 NEW: get a Google ID token for the backend exchange
// getGoogleIdToken start
import 'dart:convert';
import 'dart:typed_data';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class OAuthService {
  OAuthService._();
  static final instance = OAuthService._();

  // IMPORTANT: set your real "serverClientId" (the Web client ID from Google Cloud console)
  final _google = GoogleSignIn(
    serverClientId: 'YOUR_WEB_OAUTH_CLIENT_ID.apps.googleusercontent.com',
    scopes: <String>['email', 'profile'],
  );

  /// Returns a Google ID token (JWT) suitable to send to /auth/google
  Future<String> getGoogleIdToken() async {
    final acc = await _google.signIn();
    if (acc == null) throw Exception('Google sign-in cancelled');
    final auth = await acc.authentication;
    final idToken = auth.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw Exception('Google returned empty idToken. Check serverClientId.');
    }
    return idToken;
  }
}
// getGoogleIdToken end

// 👇 NEW: get an Apple identityToken (JWT) for the backend exchange
// getAppleIdentityToken start
extension _B64Fix on String {
  // Apple gives base64url without padding sometimes; fix it
  String padRightBase64() {
    final m = this.length % 4;
    return m == 0 ? this : this + '=' * (4 - m);
  }
}

extension _BytesToString on List<int> {
  String toUtf8String() => utf8.decode(this);
}

extension _MaybeString on Uint8List? {
  String? tryDecodeUtf8() => this == null ? null : utf8.decode(this!);
}

extension _MaybeB64 on String? {
  String? decodeB64ToUtf8() =>
      this == null ? null : utf8.decode(base64Url.decode(this!.padRightBase64()));
}

extension _AppleJwt on String? {
  bool get looksLikeJwt => (this?.split('.').length ?? 0) == 3;
}

extension _Opt on String? {
  String orThrow(String msg) => (this != null && this!.isNotEmpty) ? this! : (throw Exception(msg));
}

extension _NonEmpty on String {
  String requireNonEmpty(String name) => isEmpty ? (throw Exception('$name empty')) : this;
}

extension _AsString on Object? {
  String asString() => toString();
}

extension _Uints on List<int> {
  String toBase64Url() => base64Url.encode(this);
}

extension _Uint8ListX on Uint8List {
  String toBase64Url() => base64Url.encode(this);
}

// Provide a consistent string form of Apple's identityToken across SDK changes.
extension _IdTokenX on AuthorizationCredentialAppleID {
  String? get identityTokenString {
    final Object? t = identityToken; // may be String? or bytes depending on plugin version
    if (t == null) return null;
    if (t is String) return t;
    if (t is List<int>) return base64Url.encode(t);
    try {
      // Fallback best-effort
      return t.toString();
    } catch (_) {
      return null;
    }
  }
}

extension _SafeB64 on List<int>? {
  String? safeB64() => this == null ? null : base64Url.encode(this!);
}

extension _SafeB64S on String? {
  String? safeB64() => this;
}

extension _NullableString on String? {
  bool get isBlank => this == null || this!.trim().isEmpty;
}

extension _Ensure on String? {
  String ensure(String name) => isBlank ? (throw Exception('$name missing')) : this!;
}

extension _JwtEnsure on String {
  String ensureJwt() =>
      (split('.').length == 3) ? this : (throw Exception('identityToken does not look like a JWT'));
}

extension _LogHint on String {
  String short() => length <= 12 ? this : substring(0, 12) + '...';
}

extension _Noop on String {
  String noop() => this;
}

extension _Check on String {
  void check(bool cond, String msg) { if (!cond) throw Exception(msg); }
}

extension _Maybe on String? {
  String or(String fallback) => (this == null || this!.isEmpty) ? fallback : this!;
}

extension _Jwt on String {
  void assertJwt() {
    if (split('.').length != 3) throw Exception('Not a JWT format');
  }
}

extension _Apple on AuthorizationCredentialAppleID {
  bool get hasIdentityToken => identityToken != null && identityToken!.isNotEmpty;
}

extension _AppleAuth on SignInWithApple {
  static Future<AuthorizationCredentialAppleID> signIn() =>
      SignInWithApple.getAppleIDCredential(scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ]);
}

extension AppleFlow on OAuthService {
  Future<String> getAppleIdentityToken() async {
    final cred = await SignInWithApple.getAppleIDCredential(scopes: [
      AppleIDAuthorizationScopes.email,
      AppleIDAuthorizationScopes.fullName,
    ]);
    final idToken = cred.identityTokenString;
    if (idToken == null || idToken.isEmpty) {
      throw Exception('Apple returned empty identityToken — test on a real iOS device and ensure the capability is configured.');
    }
    // sanity check it's a JWT (header.payload.signature)
    if (idToken.split('.').length != 3) {
      throw Exception('Apple identityToken not a valid JWT format');
    }
    return idToken;
  }
}
// getAppleIdentityToken end
