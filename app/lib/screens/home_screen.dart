import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../models/deck.dart';
import '../providers/auth_provider.dart';
import '../api/api_client.dart';
import 'deck_screen.dart';
import 'study_screen.dart';

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
        _error = e.toString();
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
          title: const Text('New deck'),
          content: TextField(
            controller: c,
            decoration: const InputDecoration(labelText: 'Name'),
            autofocus: true,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim().isEmpty ? 'Deck' : c.text.trim()),
              child: const Text('Create'),
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Decks')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final decks = _decks ?? [];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Decks'),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _createDeck),
          IconButton(icon: const Icon(Icons.settings), onPressed: () => context.go('/settings')),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: decks.length,
          itemBuilder: (context, i) {
            final d = decks[i];
            final due = _dueCounts?[d.id] ?? 0;
            return Card(
              child: ListTile(
                title: Text(d.name),
                subtitle: Text('$due due today'),
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
          },
        ),
      ),
    );
  }
}
