import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.onAuth});

  final void Function(Map<String, String>)? onAuth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String? _error;
  bool _loading = false;

  Future<void> _signInWithGoogle() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    final auth = context.read<AuthProvider>();
    final err = await auth.signInWithGoogle();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('English Words', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Учите слова с интервальным повторением', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 48),
              FilledButton.icon(
                onPressed: _loading ? null : _signInWithGoogle,
                icon: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.login),
                label: Text(_loading ? 'Вход...' : 'Войти через Google'),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
              ),
              if (kGoogleWebClientId.isEmpty) ...[
                const SizedBox(height: 8),
                Text('Укажите kGoogleWebClientId в lib/core/constants.dart', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
