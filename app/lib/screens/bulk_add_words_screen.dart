import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../core/app_theme.dart';
import '../core/pos_colors.dart';
import '../providers/auth_provider.dart';

class BulkAddWordsScreen extends StatefulWidget {
  const BulkAddWordsScreen({super.key, required this.deckId});

  final String deckId;

  @override
  State<BulkAddWordsScreen> createState() => _BulkAddWordsScreenState();
}

class _BulkAddWordsScreenState extends State<BulkAddWordsScreen> {
  final _wordsController = TextEditingController();
  bool _enriching = false;
  bool _saving = false;
  String _progress = '';
  final Map<String, EnrichWordResult> _resultsByWord = {};
  final Map<String, Set<int>> _selectedByWord = {};
  final List<String> _wordOrder = [];

  static List<String> _parseWords(String text) {
    final parts = text.split(RegExp(r'[\n,;]+'));
    final words = <String>[];
    for (final p in parts) {
      final w = p.trim();
      if (w.isNotEmpty) words.add(w);
    }
    return words;
  }

  Future<void> _enrichAll() async {
    final words = _parseWords(_wordsController.text);
    if (words.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите слова (по одному в строке или через запятую)')));
      return;
    }
    if (words.length > 30) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Максимум 30 слов за раз')));
      return;
    }
    setState(() {
      _enriching = true;
      _resultsByWord.clear();
      _selectedByWord.clear();
      _wordOrder.clear();
      _wordOrder.addAll(words);
    });
    final api = context.read<AuthProvider>().api;
    for (var i = 0; i < words.length; i++) {
      if (!mounted) break;
      final word = words[i];
      setState(() => _progress = 'Обработано ${i + 1} из ${words.length}');
      try {
        final result = await api.enrichWord(word);
        if (mounted) {
          setState(() {
            _resultsByWord[word] = result;
            _selectedByWord[word] = {for (var j = 0; j < result.senses.length; j++) j};
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _resultsByWord[word] = EnrichWordResult(
              translation: '',
              example: '',
              senses: [],
            );
            _selectedByWord[word] = {};
          });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка для «$word»: $e')));
        }
      }
    }
    if (mounted) setState(() => _enriching = false);
  }

  Future<void> _saveSelected() async {
    var totalSelected = 0;
    for (final word in _wordOrder) {
      totalSelected += _selectedByWord[word]?.length ?? 0;
    }
    if (totalSelected == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Выберите хотя бы один перевод')));
      return;
    }
    setState(() => _saving = true);
    var saved = 0;
    var skipped = 0;
    try {
      final api = context.read<AuthProvider>().api;
      for (final word in _wordOrder) {
        final result = _resultsByWord[word];
        final indices = _selectedByWord[word];
        if (result == null || indices == null) continue;
        for (final i in indices) {
          if (i < 0 || i >= result.senses.length) continue;
          final sense = result.senses[i];
          try {
            await api.createCard(
              widget.deckId,
              word: word,
              translation: sense.translation,
              example: sense.example.isEmpty ? null : sense.example,
              transcription: result.transcription,
              pronunciationUrl: result.pronunciationUrl,
              partOfSpeech: sense.partOfSpeech.isEmpty ? null : sense.partOfSpeech,
            );
            saved++;
          } on DioException catch (e) {
            if (e.response?.statusCode == 409) skipped++;
            else rethrow;
          }
        }
      }
      if (mounted) {
        String msg = 'Добавлено: $saved';
        if (skipped > 0) msg += ', пропущено (уже в колоде): $skipped';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _wordsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasResults = _resultsByWord.isNotEmpty && !_enriching;
    return Scaffold(
      appBar: AppBar(title: const Text('Добавить несколько слов')),
      body: SingleChildScrollView(
        padding: AppTheme.paddingScreen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _wordsController,
              decoration: const InputDecoration(
                labelText: 'Слова',
                hintText: 'по одному слову в строке или через запятую',
                alignLabelWithHint: true,
              ),
              maxLines: 6,
              textCapitalization: TextCapitalization.none,
              enabled: !_enriching,
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: _enriching ? null : _enrichAll,
              child: _enriching
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        if (_progress.isNotEmpty) ...[
                          const SizedBox(width: 12),
                          Text(_progress),
                        ],
                      ],
                    )
                  : const Text('Перевести и добавить'),
            ),
            if (hasResults) ...[
              const SizedBox(height: 24),
              Text('Выберите переводы для добавления в колоду', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 12),
              ..._wordOrder.map((word) {
                final result = _resultsByWord[word];
                final selected = _selectedByWord[word] ?? {};
                if (result == null || result.senses.isEmpty) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(title: Text(word), subtitle: const Text('Не удалось получить перевод')),
                  );
                }
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(word, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                        if (result.transcription != null && result.transcription!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('/${result.transcription}/', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
                          ),
                        const SizedBox(height: 8),
                        ...List.generate(result.senses.length, (i) {
                          final sense = result.senses[i];
                          final isSelected = selected.contains(i);
                          final posColor = PosColors.colorFor(sense.partOfSpeech.isEmpty ? null : sense.partOfSpeech);
                          final posLabel = PosColors.labelFor(sense.partOfSpeech.isEmpty ? null : sense.partOfSpeech);
                          return InkWell(
                            onTap: () => setState(() {
                              if (isSelected) _selectedByWord[word]!.remove(i);
                              else _selectedByWord[word]!.add(i);
                            }),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Checkbox(
                                    value: isSelected,
                                    onChanged: (v) => setState(() {
                                      if (v == true) _selectedByWord[word]!.add(i);
                                      else _selectedByWord[word]!.remove(i);
                                    }),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (posLabel.isNotEmpty)
                                          Chip(
                                            label: Text(posLabel, style: const TextStyle(fontSize: 12)),
                                            backgroundColor: posColor.withValues(alpha: 0.2),
                                            side: BorderSide(color: posColor),
                                            padding: EdgeInsets.zero,
                                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          ),
                                        Text(sense.translation),
                                        if (sense.example.isNotEmpty)
                                          Text(sense.example, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _saveSelected,
                child: _saving
                    ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Добавить выбранные в колоду'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
