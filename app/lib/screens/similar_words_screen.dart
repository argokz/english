import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../core/app_theme.dart';
import '../models/similar_word.dart';
import '../providers/auth_provider.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_overlay.dart';

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
      if (mounted) {
        String msg = 'Ошибка: $e';
        if (e is DioException && e.response?.statusCode == 409) {
          msg = (e.response?.data as Map<String, dynamic>?)?['detail'] as String? ?? 'Слово уже есть в колоде';
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Похожие слова')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: AppTheme.paddingScreen,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _wordController,
                        decoration: const InputDecoration(
                          hintText: 'Введите слово',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onSubmitted: (_) => _search(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _loading ? null : _search,
                      style: FilledButton.styleFrom(minimumSize: const Size(0, AppTheme.buttonMinHeight)),
                      child: const Text('Искать'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SegmentedButton<SimilarMode>(
                  segments: const [
                    ButtonSegment(value: SimilarMode.embedding, label: Text('По смыслу'), icon: Icon(Icons.auto_awesome, size: 20)),
                    ButtonSegment(value: SimilarMode.synonyms, label: Text('Синонимы'), icon: Icon(Icons.sort_by_alpha, size: 20)),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => setState(() => _mode = s.first),
                  style: ButtonStyle(
                    padding: WidgetStateProperty.all(const EdgeInsets.symmetric(vertical: 12, horizontal: 16)),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const LoadingOverlay(message: 'Поиск…', compact: true)
                : _error != null
                    ? EmptyState(
                        icon: Icons.error_outline,
                        message: _error!,
                        actionLabel: 'Повторить',
                        onAction: () {
                          setState(() => _error = null);
                          _search();
                        },
                      )
                    : _mode == SimilarMode.synonyms && _synonymsResult != null
                        ? _buildSynonymsContent()
                        : _mode == SimilarMode.embedding && _results != null && _results!.isEmpty
                            ? const EmptyState(
                                icon: Icons.search_off,
                                message: 'Похожих слов не найдено или ещё нет эмбеддингов. Добавьте слова в колоду.',
                              )
                            : _mode == SimilarMode.embedding && _results != null && _results!.isNotEmpty
                                ? ListView.builder(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    itemCount: _results!.length,
                                    itemBuilder: (context, i) {
                                      final sw = _results![i];
                                      return Card(
                                        child: ListTile(
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                          title: Text(sw.word),
                                          subtitle: Text(sw.translation),
                                          trailing: FilledButton.tonalIcon(
                                            icon: const Icon(Icons.add, size: 20),
                                            label: const Text('В колоду'),
                                            onPressed: () => _addToDeck(sw),
                                            style: FilledButton.styleFrom(
                                              minimumSize: const Size(0, 40),
                                              padding: const EdgeInsets.symmetric(horizontal: 12),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  )
                                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildSynonymsContent() {
    final res = _synonymsResult!;
    final hasSynonyms = res.synonyms.isNotEmpty;
    final hasInDeck = res.cardsInDeck.isNotEmpty;
    if (!hasSynonyms && !hasInDeck) {
      return const EmptyState(icon: Icons.sort_by_alpha, message: 'Синонимы не найдены');
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        if (hasSynonyms) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Синонимы', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: res.synonyms.map((w) => Chip(label: Text(w), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8))).toList(),
          ),
          const SizedBox(height: 20),
        ],
        if (hasInDeck) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Уже в колоде', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
          ...res.cardsInDeck.map((sw) => Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              title: Text(sw.word),
              subtitle: Text(sw.translation),
              trailing: Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary, size: 24),
            ),
          )),
        ],
      ],
    );
  }
}
