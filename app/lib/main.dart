import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:app_links/app_links.dart';
import 'core/app_theme.dart';
import 'providers/auth_provider.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/ielts_writing_screen.dart';

void main() {
  final authProvider = AuthProvider();
  runApp(ChangeNotifierProvider<AuthProvider>.value(
    value: authProvider,
    child: EnglishWordsApp(authProvider: authProvider),
  ));
}

class EnglishWordsApp extends StatefulWidget {
  const EnglishWordsApp({super.key, required this.authProvider});

  final AuthProvider authProvider;

  @override
  State<EnglishWordsApp> createState() => _EnglishWordsAppState();
}

class _EnglishWordsAppState extends State<EnglishWordsApp> {
  @override
  void initState() {
    super.initState();
    _listenForDeepLink();
  }

  void _listenForDeepLink() {
    final appLinks = AppLinks();
    void handleUri(Uri? uri) {
      if (uri == null || uri.fragment.isEmpty) return;
      final params = <String, String>{};
      for (final part in uri.fragment.split('&')) {
        final kv = part.split('=');
        if (kv.length >= 2) {
          params[Uri.decodeComponent(kv[0])] = Uri.decodeComponent(kv[1]);
        }
      }
      if (params.containsKey('access_token')) {
        widget.authProvider.saveFromCallback(params);
      }
    }
    appLinks.getInitialLink().then(handleUri);
    appLinks.uriLinkStream.listen(handleUri);
  }

  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      initialLocation: '/',
      refreshListenable: widget.authProvider,
      redirect: (context, state) {
        final auth = context.read<AuthProvider>();
        if (!auth.isLoggedIn && state.uri.path != '/login') return '/login';
        if (auth.isLoggedIn && state.uri.path == '/login') return '/';
        return null;
      },
      routes: [
        GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
        GoRoute(
          path: '/',
          builder: (_, __) => const HomeScreen(),
          routes: [
            GoRoute(path: 'settings', builder: (_, __) => const SettingsScreen()),
            GoRoute(path: 'writing', builder: (_, __) => const IeltsWritingScreen()),
          ],
        ),
      ],
    );
    return MaterialApp.router(
      title: 'English Words',
      theme: AppTheme.theme,
      routerConfig: router,
    );
  }
}
