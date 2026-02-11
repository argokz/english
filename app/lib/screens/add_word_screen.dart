import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import '../api/api_client.dart';
import '../core/app_theme.dart';
import '../core/pos_colors.dart';
import '../providers/auth_provider.dart';

class AddWordScreen extends StatefulWidget {
  const AddWordScreen({super.key, required this.deckId});

  final String deckId;

  @override
  State<AddWordScreen> createState() => _AddWordScreenState();
}

class _AddWordScreenState extends State<AddWordScreen> {
  final _wordController = TextEditingController();
  bool _loading = false;
  bool _enriching = false;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _inputIsRussian = false; // false = English, true = Russian

  EnrichWordResult? _enrichResult;
  final Set<int> _selectedSenseIndices = {};

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  String? get _pronunciationUrl => _enrichResult?.pronunciationUrl;

  Future<void> _playWord() async {
    final word = (_enrichResult?.word ?? _wordController.text).trim();
    if (word.isEmpty) return;
    try {
      if (_pronunciationUrl != null && _pronunciationUrl!.isNotEmpty) {
        await _audioPlayer.play(UrlSource(_pronunciationUrl!));
      } else {
        final url = 'https://translate.google.com/translate_tts?ie=UTF-8&tl=en&client=tw-ob&q=${Uri.encodeComponent(word)}';
        await _audioPlayer.play(UrlSource(url));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка воспроизведения: $e')));
    }
  }

  Future<void> _enrich() async {
    final word = _wordController.text.trim();
    if (word.isEmpty || _enriching) return;
    setState(() => _enriching = true);
    try {
      final result = await context.read<AuthProvider>().api.enrichWord(
            word,
            sourceLang: _inputIsRussian ? 'ru' : 'en',
          );
      if (mounted) {
        setState(() {
          _enrichResult = result;
          _selectedSenseIndices.clear();
          for (var i = 0; i < result.senses.length; i++) {
            _selectedSenseIndices.add(i);
          }
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка подсказки: $e')));
    } finally {
      if (mounted) setState(() => _enriching = false);
    }
  }

  Future<void> _save() async {
    final inputText = _wordController.text.trim();
    if (inputText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите слово')));
      return;
    }
    if (_enrichResult == null || _selectedSenseIndices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Нажмите «Подсказать» и выберите переводы для сохранения')));
      return;
    }
    final wordForCard = _enrichResult!.word ?? inputText; // всегда английское слово на карточке
    setState(() => _loading = true);
    var saved = 0;
    var skipped = 0;
    try {
      final api = context.read<AuthProvider>().api;
      final r = _enrichResult!;
      for (final i in _selectedSenseIndices) {
        if (i < 0 || i >= r.senses.length) continue;
        final sense = r.senses[i];
        try {
          await api.createCard(
            widget.deckId,
            word: wordForCard,
            translation: sense.translation,
            example: sense.example.isEmpty ? null : sense.example,
            transcription: r.transcription,
            pronunciationUrl: r.pronunciationUrl,
            partOfSpeech: sense.partOfSpeech.isEmpty ? null : sense.partOfSpeech,
            examples: sense.examples.isNotEmpty ? sense.examples : null,
          );
          saved++;
        } on DioException catch (e) {
          if (e.response?.statusCode == 409) {
            skipped++;
          } else {
            rethrow;
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
        String msg = 'Ошибка: $e';
        if (e is DioException && e.response?.statusCode == 409) {
          msg = (e.response?.data as Map<String, dynamic>?)?['detail'] as String? ?? 'Слово уже есть в колоде';
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasResult = _enrichResult != null && _enrichResult!.senses.isNotEmpty;
    final transcription = _enrichResult?.transcription;
    return Scaffold(
      appBar: AppBar(title: const Text('Добавить слово')),
      body: SingleChildScrollView(
        padding: AppTheme.paddingScreen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('English')),
                ButtonSegment(value: true, label: Text('Русский')),
              ],
              selected: {_inputIsRussian},
              onSelectionChanged: (s) => setState(() => _inputIsRussian = s.first),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _wordController,
                    decoration: InputDecoration(
                      labelText: _inputIsRussian ? 'Слово (рус.)' : 'Слово (англ.)',
                      hintText: _inputIsRussian ? 'книга' : 'apple',
                    ),
                    textCapitalization: TextCapitalization.none,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.volume_up),
                  onPressed: _playWord,
                  tooltip: 'Произношение',
                  style: IconButton.styleFrom(
                    minimumSize: const Size(AppTheme.buttonMinHeight, AppTheme.buttonMinHeight),
                  ),
                ),
              ],
            ),
            if (transcription != null && transcription.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('Транскрипция: ', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  Text('/$transcription/', style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontStyle: FontStyle.italic)),
                ],
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: _enriching ? null : _enrich,
              style: FilledButton.styleFrom(minimumSize: const Size(0, AppTheme.buttonMinHeight)),
              child: _enriching
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Подсказать'),
            ),
            if (hasResult) ...[
              const SizedBox(height: 20),
              Card(
                elevation: 1,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Слово', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _wordController.text.trim(),
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (_enrichResult!.word != null && (_enrichResult!.word!.trim().toLowerCase() != _wordController.text.trim().toLowerCase()))
                            Text('→ ', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))
                          else const SizedBox.shrink(),
                          if (_enrichResult!.word != null && (_enrichResult!.word!.trim().toLowerCase() != _wordController.text.trim().toLowerCase()))
                            Text(_enrichResult!.word!, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontStyle: FontStyle.italic)),
                        ],
                      ),
                      if (transcription != null && transcription.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text('/$transcription/', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Переводы по частям речи и примеры', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 10),
              ...List.generate(_enrichResult!.senses.length, (i) {
                final sense = _enrichResult!.senses[i];
                final selected = _selectedSenseIndices.contains(i);
                final posLabel = sense.partOfSpeech.isNotEmpty ? PosColors.labelFor(sense.partOfSpeech) : 'Перевод';
                final posColor = PosColors.colorFor(sense.partOfSpeech.isEmpty ? null : sense.partOfSpeech);
                final translationLines = sense.translation.trim().isEmpty ? <String>[] : sense.translation.split(RegExp(r';\s*'));
                final allExamples = sense.examples.isNotEmpty ? sense.examples : (sense.example.isNotEmpty ? [sense.example] : <String>[]);
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    side: BorderSide(color: selected ? posColor : Theme.of(context).dividerColor, width: selected ? 2 : 1),
                  ),
                  child: InkWell(
                    onTap: () => setState(() {
                      if (selected) _selectedSenseIndices.remove(i); else _selectedSenseIndices.add(i);
                    }),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: selected,
                            onChanged: (v) => setState(() {
                              if (v == true) _selectedSenseIndices.add(i); else _selectedSenseIndices.remove(i);
                            }),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Chip(
                                  label: Text(posLabel, style: const TextStyle(fontSize: 12)),
                                  backgroundColor: posColor.withValues(alpha: 0.2),
                                  side: BorderSide(color: posColor, width: 1),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                const SizedBox(height: 10),
                                if (translationLines.isNotEmpty)
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: translationLines.map((line) => Text(line.trim(), style: Theme.of(context).textTheme.bodyLarge)).toList(),
                                  ),
                                if (translationLines.isEmpty && sense.translation.isNotEmpty)
                                  Text(sense.translation, style: Theme.of(context).textTheme.bodyLarge),
                                if (allExamples.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Text('Примеры:', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Theme.of(context).colorScheme.primary)),
                                  const SizedBox(height: 4),
                                  ...allExamples.map((ex) => Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Text(ex, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic), maxLines: 3, overflow: TextOverflow.ellipsis),
                                  )),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loading ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, AppTheme.buttonMinHeight + 8),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _loading
                    ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_selectedSenseIndices.length == 1 ? 'Добавить карточку' : 'Добавить карточки (${_selectedSenseIndices.length})'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
