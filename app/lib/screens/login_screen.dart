import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.onAuth});

  final void Function(Map<String, String>)? onAuth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _urlController = TextEditingController();
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

  Future<void> _openGoogleLoginInBrowser() async {
    final auth = context.read<AuthProvider>();
    final uri = Uri.parse(auth.googleLoginUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      setState(() => _error = 'Cannot open browser');
    }
  }

  void _handlePastedUrl() {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    // Support both full redirect URL and fragment: englishapp://auth#access_token=xxx&user_id=...
    final fragment = url.contains('#') ? url.split('#').last : url;
    final params = <String, String>{};
    for (final part in fragment.split('&')) {
      final kv = part.split('=');
      if (kv.length >= 2) {
        params[Uri.decodeComponent(kv[0])] = Uri.decodeComponent(kv[1]);
      }
    }
    if (params.containsKey('access_token')) {
      context.read<AuthProvider>().saveFromCallback(params);
      _urlController.clear();
      setState(() => _error = null);
    } else {
      setState(() => _error = 'Paste the URL you were redirected to after login (with #access_token=...)');
    }
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
              const Text('Learn words with spaced repetition', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 48),
              FilledButton.icon(
                onPressed: _loading ? null : _signInWithGoogle,
                icon: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.login),
                label: Text(_loading ? 'Signing in...' : 'Sign in with Google'),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
              ),
              if (kGoogleWebClientId.isEmpty) ...[
                const SizedBox(height: 8),
                Text('Set kGoogleWebClientId in lib/core/constants.dart for native sign-in.', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _openGoogleLoginInBrowser,
                icon: const Icon(Icons.open_in_browser, size: 18),
                label: const Text('Open in browser instead'),
              ),
              const SizedBox(height: 24),
              const Text('After login you will be redirected. If the app did not open, paste the redirect URL below:'),
              const SizedBox(height: 12),
              TextField(
                controller: _urlController,
                decoration: const InputDecoration(
                  hintText: 'Paste URL with #access_token=...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: _handlePastedUrl, child: const Text('Submit pasted URL')),
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
