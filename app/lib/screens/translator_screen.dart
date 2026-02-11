import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../core/app_theme.dart';
import '../core/pos_colors.dart';
import '../models/deck.dart';
import '../providers/auth_provider.dart';

class TranslatorScreen extends StatefulWidget {
  const TranslatorScreen({super.key});

  @override
  State<TranslatorScreen> createState() => _TranslatorScreenState();
}

class _TranslatorScreenState extends State<TranslatorScreen> {
  final _sourceController = TextEditingController();
  bool _ruToEn = true; // true: RU → EN, false: EN → RU
  bool _loading = false;
  TranslateResult? _result;
  String? _error;
  EnrichWordResult? _enrichResult;
  final Set<int> _selectedSenseIndices = {};
  bool _loadingEnrich = false;

  @override
  void dispose() {
    _sourceController.dispose();
    super.dispose();
  }

  String get _sourceLang => _ruToEn ? 'ru' : 'en';
  String get _targetLang => _ruToEn ? 'en' : 'ru';

  Future<void> _translate() async {
    final text = _sourceController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите текст для перевода')));
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final res = await context.read<AuthProvider>().api.translate(
            text,
            sourceLang: _sourceLang,
            targetLang: _targetLang,
          );
      if (mounted) setState(() {
        _result = res;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  /// English word for card (word side), Russian for translation side.
  String? get _englishWord => _result == null
      ? null
      : _ruToEn
          ? _result!.translation.trim()
          : _sourceController.text.trim();
  String? get _russianTranslation => _result == null
      ? null
      : _ruToEn
          ? _sourceController.text.trim()
          : _result!.translation.trim();

  bool get _isSingleEnglishWord {
    final en = _englishWord;
    if (en == null || en.isEmpty) return false;
    return en.split(RegExp(r'\s+')).length == 1;
  }

  Future<void> _loadSenses() async {
    final english = _englishWord;
    if (english == null || english.isEmpty || !_isSingleEnglishWord || _loadingEnrich) return;
    setState(() {
      _loadingEnrich = true;
      _enrichResult = null;
      _selectedSenseIndices.clear();
    });
    try {
      final result = await context.read<AuthProvider>().api.enrichWord(english);
      if (mounted) {
        setState(() {
          _enrichResult = result;
          for (var i = 0; i < result.senses.length; i++) _selectedSenseIndices.add(i);
          _loadingEnrich = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingEnrich = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  Future<void> _addToDeck() async {
    final english = _englishWord;
    final russian = _russianTranslation;
    if (english == null || english.isEmpty || russian == null || russian.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Сначала выполните перевод')));
      return;
    }
    final api = context.read<AuthProvider>().api;
    List<Deck> decks;
    try {
      decks = await api.getDecks();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка загрузки колод: $e')));
      return;
    }
    if (decks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Создайте колоду в главном меню')));
      return;
    }
    final deck = await showModalBottomSheet<Deck>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Выберите колоду', style: Theme.of(ctx).textTheme.titleMedium),
            ),
            ...decks.map((d) => ListTile(
                  title: Text(d.name),
                  onTap: () => Navigator.pop(ctx, d),
                )),
          ],
        ),
      ),
    );
    if (deck == null) return;
    setState(() => _loading = true);
    try {
      final hasSenses = _enrichResult != null && _selectedSenseIndices.isNotEmpty;
      if (hasSenses) {
        var saved = 0, skipped = 0;
        final r = _enrichResult!;
        for (final i in _selectedSenseIndices) {
          if (i < 0 || i >= r.senses.length) continue;
          final sense = r.senses[i];
          try {
            await api.createCard(
              deck.id,
              word: english,
              translation: sense.translation,
              example: sense.example.isEmpty ? null : sense.example,
              transcription: r.transcription,
              pronunciationUrl: r.pronunciationUrl,
              partOfSpeech: sense.partOfSpeech.isEmpty ? null : sense.partOfSpeech,
            );
            saved++;
          } on DioException catch (e) {
            if (e.response?.statusCode == 409) skipped++;
            else rethrow;
          }
        }
        if (mounted) {
          String msg = 'Добавлено: $saved';
          if (skipped > 0) msg += ', пропущено: $skipped';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        }
      } else {
        String? transcription;
        String? pronunciationUrl;
        String? example;
        if (_enrichResult != null && _enrichResult!.senses.isNotEmpty) {
          transcription = _enrichResult!.transcription;
          pronunciationUrl = _enrichResult!.pronunciationUrl;
          example = _enrichResult!.senses.first.example.isEmpty ? null : _enrichResult!.senses.first.example;
        }
        await api.createCard(
          deck.id,
          word: english,
          translation: russian,
          example: example,
          transcription: transcription,
          pronunciationUrl: pronunciationUrl,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Добавлено в колоду «${deck.name}»')));
        }
      }
    } on DioException catch (e) {
      if (mounted) {
        final msg = e.response?.statusCode == 409
            ? 'Это слово уже есть в колоде'
            : 'Ошибка: ${e.message}';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasResult = _result != null && _result!.translation.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Переводчик')),
      body: SingleChildScrollView(
        padding: AppTheme.paddingScreen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Рус → En'), icon: Icon(Icons.translate)),
                ButtonSegment(value: false, label: Text('En → Рус'), icon: Icon(Icons.translate)),
              ],
              selected: {_ruToEn},
              onSelectionChanged: (s) => setState(() => _ruToEn = s.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _sourceController,
              decoration: InputDecoration(
                labelText: _ruToEn ? 'Текст на русском' : 'Text in English',
                hintText: _ruToEn ? 'например: книга' : 'e.g. book',
                border: const OutlineInputBorder(),
              ),
              maxLines: 3,
              textCapitalization: TextCapitalization.none,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _loading ? null : _translate,
              child: _loading
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Перевести'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (hasResult) ...[
              const SizedBox(height: 24),
              Text('Перевод', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    _result!.translation,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ),
              if (_isSingleEnglishWord) ...[
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: _loadingEnrich ? null : _loadSenses,
                  child: _loadingEnrich
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Получить все части речи'),
                ),
              ],
              if (_enrichResult != null && _enrichResult!.senses.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Переводы по частям речи', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                ...List.generate(_enrichResult!.senses.length, (i) {
                  final sense = _enrichResult!.senses[i];
                  final selected = _selectedSenseIndices.contains(i);
                  final posLabel = sense.partOfSpeech.isNotEmpty ? PosColors.labelFor(sense.partOfSpeech) : '';
                  final posColor = PosColors.colorFor(sense.partOfSpeech.isEmpty ? null : sense.partOfSpeech);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: InkWell(
                      onTap: () => setState(() {
                        if (selected) _selectedSenseIndices.remove(i);
                        else _selectedSenseIndices.add(i);
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            Checkbox(
                              value: selected,
                              onChanged: (v) => setState(() {
                                if (v == true) _selectedSenseIndices.add(i);
                                else _selectedSenseIndices.remove(i);
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
                    ),
                  );
                }),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loading ? null : _addToDeck,
                icon: const Icon(Icons.add_card),
                label: Text(_enrichResult != null && _selectedSenseIndices.isNotEmpty
                    ? 'Добавить выбранные в колоду'
                    : 'Добавить в колоду'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
