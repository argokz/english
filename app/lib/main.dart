import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:app_links/app_links.dart';
import 'core/app_theme.dart';
import 'providers/youtube_provider.dart';
import 'providers/auth_provider.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/ielts_writing_screen.dart';
import 'screens/translator_screen.dart';
import 'screens/ielts_listening_screen.dart';
import 'screens/ielts_exam_screen.dart';

void main() {
  final authProvider = AuthProvider();
  final youtubeProvider = YoutubeProvider(authProvider);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<YoutubeProvider>.value(value: youtubeProvider),
      ],
      child: EnglishWordsApp(authProvider: authProvider),
    ),
  );
}

class EnglishWordsApp extends StatefulWidget {
  const EnglishWordsApp({super.key, required this.authProvider});

  final AuthProvider authProvider;

  @override
  State<EnglishWordsApp> createState() => _EnglishWordsAppState();
}

class _EnglishWordsAppState extends State<EnglishWordsApp> {
  bool _authLoaded = false;
  // Router is created once after secure storage loads — avoids redirect
  // firing on every rebuild before the token is read.
  GoRouter? _router;

  GoRouter _buildRouter() {
    return GoRouter(
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
            GoRoute(path: 'listening', builder: (_, __) => const IeltsListeningScreen()),
            GoRoute(path: 'exam', builder: (_, __) => const IeltsExamScreen()),
            GoRoute(path: 'translator', builder: (_, __) => const TranslatorScreen()),
          ],
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _listenForDeepLink();
    widget.authProvider.ensureStorageLoaded().then((_) {
      if (mounted) {
        setState(() {
          _authLoaded = true;
          _router = _buildRouter();
        });
      }
    });
    // Если хранилище зависло — через 8 сек всё равно показываем экран.
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted && !_authLoaded) {
        setState(() {
          _authLoaded = true;
          _router ??= _buildRouter();
        });
      }
    });
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
    if (!_authLoaded || _router == null) {
      return MaterialApp(
        title: 'English Words',
        theme: AppTheme.theme,
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return MaterialApp.router(
      title: 'English Words',
      theme: AppTheme.theme,
      routerConfig: _router!,
    );
  }
}
