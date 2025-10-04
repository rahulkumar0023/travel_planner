import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/oauth.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.api});
  final ApiService api;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _busy = false;
  String? _error;

  // 👇 NEW: state fields for status
  // signin screen fields start
  String? _currentEmail;
  bool _restored = false;
  // signin screen fields end

  // 👇 NEW: restore session on open
  // signin screen initState start
  @override
  void initState() {
    super.initState();
    () async {
      // 👇 NEW: if session restored, skip sign-in and go to Home
      // auto-forward after restore start
      final ok = await widget.api.restoreSession();
      if (ok) {
        try {
          final me = await widget.api.getMe();
          if (!mounted) return;
          Navigator.of(context)
              .pushNamedAndRemoveUntil('/home', (route) => false);
          return; // stop building sign-in UI
        } catch (_) {
          // token invalid → fall through to sign-in UI
        }
      }
      // auto-forward after restore end
      if (mounted) setState(() => _restored = true);
    }();
  }
  // signin screen initState end

  Future<void> _google() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final idToken = await OAuthService.instance.getGoogleIdToken();
      await widget.api.loginWithIdToken(idToken: idToken, provider: 'google');
      if (!mounted) return;
      // 👇 Update: after successful sign-in, go to Home
      // navigate to home after login start
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
      // navigate to home after login end
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apple() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final idToken = await OAuthService.instance.getAppleIdentityToken();
      await widget.api.loginWithIdToken(idToken: idToken, provider: 'apple');
      // Optional: fetch user profile for logging
      try {
        final me = await widget.api.getMe();
        // ignore: avoid_print
        // ignore: use_build_context_synchronously
        debugPrint("[Auth] signed in as ${me['email']}");
      } catch (_) {}
      if (!mounted) return;
      // 👇 Update: after successful sign-in, go to Home
      // navigate to home after login start
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
      // navigate to home after login end
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child:
                    Text(_error!, style: TextStyle(color: Colors.red.shade400)),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _google,
                icon: const Icon(Icons.login),
                label: const Text(
                  'Continue with Google',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _apple,
                icon: const Icon(Icons.apple),
                label: const Text(
                  'Continue with Apple',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // 👇 NEW: UI buttons (put inside your build method's widget tree, e.g., in a Column)
            // signin actions start
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                // Dev Sign-in
                ElevatedButton(
                  onPressed: () async {
                    try {
                      // 👇 Update: after successful sign-in, go to Home
                      // navigate to home after login start
                      await widget.api.signInDevAndFetch('rahul@example.com');
                      final me = await widget.api.getMe();
                      if (!context.mounted) return;
                      Navigator.of(context)
                          .pushNamedAndRemoveUntil('/home', (route) => false);
                      // navigate to home after login end
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Dev sign-in failed: $e')),
                      );
                    }
                  },
                  child: const Text('Sign in (Dev)'),
                ),

                // OPTIONAL: Google / Apple buttons (enable when providers ready)
                // ElevatedButton(
                //   onPressed: () async {
                //     await OAuthService.instance.signInWithGoogle();
                //     final me = await ApiService.instance.getMe();
                //     if (!context.mounted) return;
                //     setState(() => _currentEmail = (me['email'] as String?) ?? '(unknown)');
                //   },
                //   child: const Text('Sign in with Google'),
                // ),
                // ElevatedButton(
                //   onPressed: () async {
                //     await OAuthService.instance.signInWithApple();
                //     final me = await ApiService.instance.getMe();
                //     if (!context.mounted) return;
                //     setState(() => _currentEmail = (me['email'] as String?) ?? '(unknown)');
                //   },
                //   child: const Text('Sign in with Apple'),
                // ),

                // Sign out
                OutlinedButton(
                  onPressed: () async {
                    // 👇 Update: after sign-out, go to Sign-in
                    // navigate to sign-in after logout start
                    await widget.api.signOut();
                    if (!context.mounted) return;
                    Navigator.of(context)
                        .pushNamedAndRemoveUntil('/sign-in', (route) => false);
                    // navigate to sign-in after logout end
                  },
                  child: const Text('Sign out'),
                ),
              ],
            ),
            // signin actions end

            // 👇 NEW: status text (drop this anywhere in the UI to show session info)
            // signin status start
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _currentEmail == null
                    ? (_restored ? 'Not signed in' : 'Restoring session…')
                    : 'Signed in as: $_currentEmail',
              ),
            ),
            // signin status end
            const SizedBox(height: 20),
            if (_busy) const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
