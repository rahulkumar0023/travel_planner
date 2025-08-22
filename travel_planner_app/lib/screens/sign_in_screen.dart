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

  Future<void> _google() async {
    setState(() { _busy = true; _error = null; });
    try {
      final idToken = await OAuthService.instance.getGoogleIdToken();
      await widget.api.loginWithIdToken(idToken: idToken, provider: 'google');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apple() async {
    setState(() { _busy = true; _error = null; });
    try {
      final idToken = await OAuthService.instance.getAppleIdentityToken();
      await widget.api.loginWithIdToken(idToken: idToken, provider: 'apple');
      if (mounted) Navigator.pop(context, true);
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
                child: Text(_error!, style: TextStyle(color: Colors.red.shade400)),
              ),
            FilledButton.icon(
              onPressed: _busy ? null : _google,
              icon: const Icon(Icons.login),
              label: const Text('Continue with Google'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _apple,
              icon: const Icon(Icons.apple),
              label: const Text('Continue with Apple'),
            ),
            const SizedBox(height: 20),
            if (_busy) const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
