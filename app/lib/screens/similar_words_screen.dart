import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/similar_word.dart';
import '../providers/auth_provider.dart';

class SimilarWordsScreen extends StatefulWidget {
  const SimilarWordsScreen({super.key, required this.deckId, required this.deckName});

  final String deckId;
  final String deckName;

  @override
  State<SimilarWordsScreen> createState() => _SimilarWordsScreenState();
}

class _SimilarWordsScreenState extends State<SimilarWordsScreen> {
  final _wordController = TextEditingController();
  List<SimilarWord>? _results;
  bool _loading = false;
  String? _error;

  Future<void> _search() async {
    final word = _wordController.text.trim();
    if (word.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _results = null;
    });
    try {
      final list = await context.read<AuthProvider>().api.similarWords(word, deckId: widget.deckId);
      setState(() {
        _results = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _addToDeck(SimilarWord sw) async {
    try {
      await context.read<AuthProvider>().api.createCard(
            widget.deckId,
            word: sw.word,
            translation: sw.translation,
            example: sw.example,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added ${sw.word}')));
        setState(() => _results = _results?.where((e) => e.cardId != sw.cardId).toList());
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Similar words')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _wordController,
                    decoration: const InputDecoration(hintText: 'Enter word', border: OutlineInputBorder()),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _loading ? null : _search, child: const Text('Search')),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            if (_results != null && _results!.isEmpty) const Text('No similar words found or no embeddings yet. Add more words first.'),
            if (_results != null && _results!.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  itemCount: _results!.length,
                  itemBuilder: (context, i) {
                    final sw = _results![i];
                    return Card(
                      child: ListTile(
                        title: Text(sw.word),
                        subtitle: Text(sw.translation),
                        trailing: IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () => _addToDeck(sw),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
