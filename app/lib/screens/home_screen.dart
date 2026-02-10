import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../api/api_client.dart';
import '../models/deck.dart';
import '../providers/auth_provider.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_overlay.dart';
import 'deck_screen.dart';
import 'study_screen.dart';
import 'ielts_writing_screen.dart';

String _errorMessage(dynamic e) {
  if (e is DioException && e.response?.data is Map) {
    final detail = e.response!.data['detail'];
    if (detail != null) return detail is String ? detail : detail.toString();
  }
  return e.toString();
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Deck>? _decks;
  Map<String, int>? _dueCounts;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<AuthProvider>().api;
      final decks = await api.getDecks();
      final counts = <String, int>{};
      for (final d in decks) {
        final due = await api.getDueCards(d.id);
        counts[d.id] = due.length;
      }
      setState(() {
        _decks = decks;
        _dueCounts = counts;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = _errorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _createDeck() async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: const Text('Новая колода'),
          content: TextField(
            controller: c,
            decoration: const InputDecoration(
              labelText: 'Название',
              hintText: 'Мои слова',
            ),
            autofocus: true,
            onSubmitted: (_) => Navigator.pop(ctx, c.text.trim().isEmpty ? 'Колода' : c.text.trim()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim().isEmpty ? 'Колода' : c.text.trim()),
              child: const Text('Создать'),
            ),
          ],
        );
      },
    );
    if (name == null) return;
    try {
      await context.read<AuthProvider>().api.createDeck(name);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: ${_errorMessage(e)}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: LoadingOverlay(message: 'Загрузка колод…'),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Колоды')),
        body: EmptyState(
          icon: Icons.error_outline,
          message: _error!,
          actionLabel: 'Повторить',
          onAction: _load,
        ),
      );
    }
    final decks = _decks ?? [];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Колоды'),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _createDeck),
          IconButton(icon: const Icon(Icons.settings), onPressed: () => context.go('/settings')),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(8),
          children: [
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Icon(Icons.edit_note, color: Theme.of(context).colorScheme.onPrimaryContainer),
                ),
                title: const Text('IELTS Письмо'),
                subtitle: const Text('Таймер, подсчёт слов, проверка и оценка текста'),
                trailing: const Icon(Icons.arrow_forward),
                onTap: () => context.push('/writing'),
              ),
            ),
            ...List.generate(decks.length, (i) {
              final d = decks[i];
            final due = _dueCounts?[d.id] ?? 0;
            return Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                title: Text(d.name),
                subtitle: Text('$due на сегодня'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (due > 0)
                      IconButton(
                        icon: const Icon(Icons.school),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => StudyScreen(deckId: d.id, deckName: d.name)),
                        ),
                      ),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => DeckScreen(deckId: d.id, deckName: d.name)),
                      ),
                    ),
                  ],
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => DeckScreen(deckId: d.id, deckName: d.name)),
                ),
              ),
            );
            }),
          ],
        ),
      ),
    );
  }
}
