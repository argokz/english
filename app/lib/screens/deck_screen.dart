import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/card.dart' as app;
import '../providers/auth_provider.dart';
import 'add_word_screen.dart';
import 'generate_words_screen.dart';
import 'study_screen.dart';
import 'similar_words_screen.dart';

class DeckScreen extends StatefulWidget {
  const DeckScreen({super.key, required this.deckId, required this.deckName});

  final String deckId;
  final String deckName;

  @override
  State<DeckScreen> createState() => _DeckScreenState();
}

class _DeckScreenState extends State<DeckScreen> {
  List<app.CardModel>? _cards;
  bool _loading = true;
  String? _error;
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _playWord(app.CardModel card) async {
    try {
      if (card.pronunciationUrl != null && card.pronunciationUrl!.isNotEmpty) {
        await _audioPlayer.play(UrlSource(card.pronunciationUrl!));
      } else {
        final url = 'https://translate.google.com/translate_tts?ie=UTF-8&tl=en&client=tw-ob&q=${Uri.encodeComponent(card.word)}';
        await _audioPlayer.play(UrlSource(url));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка воспроизведения: $e')));
    }
  }

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
      final cards = await api.getCards(widget.deckId);
      setState(() {
        _cards = cards;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.deckName),
        actions: [
          IconButton(
            icon: const Icon(Icons.school),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StudyScreen(deckId: widget.deckId, deckName: widget.deckName),
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              if (value == 'backfill') {
                final api = context.read<AuthProvider>().api;
                if (!mounted) return;
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => const Center(child: CircularProgressIndicator()),
                );
                try {
                  final updated = await api.backfillTranscriptions(deckId: widget.deckId, limit: 100);
                  if (!mounted) return;
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Обновлено карточек: $updated')),
                  );
                  _load();
                } catch (e) {
                  if (mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Ошибка: $e')),
                    );
                  }
                }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'backfill', child: Text('Обновить транскрипции')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: _load, child: const Text('Повторить')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: (_cards ?? []).length,
                    itemBuilder: (context, i) {
                      final c = _cards![i];
                      return Card(
                        child: ListTile(
                          title: Text(c.word),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(c.translation),
                              if (c.transcription != null && c.transcription!.isNotEmpty)
                                Text('/${c.transcription}/', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey[600])),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.volume_up, size: 22),
                                onPressed: () => _playWord(c),
                                tooltip: 'Произношение',
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  try {
                                    await context.read<AuthProvider>().api.deleteCard(c.id);
                                    _load();
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
                                    }
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'add',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AddWordScreen(deckId: widget.deckId),
                ),
              );
              _load();
            },
            icon: const Icon(Icons.add),
            label: const Text('Добавить слово'),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: 'generate',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GenerateWordsScreen(deckId: widget.deckId),
                ),
              );
              _load();
            },
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Сгенерировать слова'),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: 'similar',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SimilarWordsScreen(deckId: widget.deckId, deckName: widget.deckName),
                ),
              );
              _load();
            },
            icon: const Icon(Icons.lightbulb_outline),
            label: const Text('Похожие слова'),
          ),
        ],
      ),
    );
  }
}
