import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../models/similar_word.dart';
import '../providers/auth_provider.dart';

enum SimilarMode { embedding, synonyms }

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
  SynonymsResult? _synonymsResult;
  SimilarMode _mode = SimilarMode.embedding;
  bool _loading = false;
  String? _error;

  Future<void> _search() async {
    final word = _wordController.text.trim();
    if (word.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _results = null;
      _synonymsResult = null;
    });
    try {
      if (_mode == SimilarMode.synonyms) {
        final res = await context.read<AuthProvider>().api.getSynonyms(word, deckId: widget.deckId);
        setState(() {
          _synonymsResult = res;
          _loading = false;
        });
      } else {
        final list = await context.read<AuthProvider>().api.similarWords(word, deckId: widget.deckId);
        setState(() {
          _results = list;
          _loading = false;
        });
      }
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Добавлено: ${sw.word}')));
        setState(() => _results = _results?.where((e) => e.cardId != sw.cardId).toList());
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Похожие слова')),
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
                    decoration: const InputDecoration(hintText: 'Введите слово', border: OutlineInputBorder()),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _loading ? null : _search, child: const Text('Искать')),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<SimilarMode>(
              segments: const [
                ButtonSegment(value: SimilarMode.embedding, label: Text('По смыслу'), icon: Icon(Icons.auto_awesome)),
                ButtonSegment(value: SimilarMode.synonyms, label: Text('Синонимы'), icon: Icon(Icons.sort_by_alpha)),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 16),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            if (_mode == SimilarMode.synonyms && _synonymsResult != null) _buildSynonymsContent(),
            if (_mode == SimilarMode.embedding && _results != null && _results!.isEmpty)
              const Text('Похожих слов не найдено или ещё нет эмбеддингов. Добавьте слова в колоду.'),
            if (_mode == SimilarMode.embedding && _results != null && _results!.isNotEmpty)
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

  Widget _buildSynonymsContent() {
    final res = _synonymsResult!;
    final hasSynonyms = res.synonyms.isNotEmpty;
    final hasInDeck = res.cardsInDeck.isNotEmpty;
    if (!hasSynonyms && !hasInDeck) {
      return const Expanded(child: Center(child: Text('Синонимы не найдены')));
    }
    return Expanded(
      child: ListView(
        children: [
          if (hasSynonyms) ...[
            const Text('Синонимы', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: res.synonyms.map((w) => Chip(label: Text(w))).toList(),
            ),
            const SizedBox(height: 16),
          ],
          if (hasInDeck) ...[
            const Text('Уже в колоде', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 6),
            ...res.cardsInDeck.map((sw) => Card(
              child: ListTile(
                title: Text(sw.word),
                subtitle: Text(sw.translation),
                trailing: IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => _addToDeck(sw),
                ),
              ),
            )),
          ],
        ],
      ),
    );
  }
}
