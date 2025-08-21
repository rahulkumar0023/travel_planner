import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.api});
  final ApiService api;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  late final AuthService _auth;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _auth = AuthService(baseUrl: widget.api.baseUrl);
  }

  Future<void> _google() async {
    setState(() { _busy = true; _error = null; });
    try {
      final idToken = await _auth.signInWithGoogleIdToken();
      if (idToken == null) return;
      await _auth.exchangeAndStoreToken(provider: 'google', idToken: idToken);
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
      final res = await _auth.signInWithApple();
      if (res == null) return;
      final token = res.idToken ?? res.authCode;
      if (token == null) throw Exception('Auth token missing');
      await _auth.exchangeAndStoreToken(provider: 'apple', idToken: token);
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
