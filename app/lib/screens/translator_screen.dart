import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../core/app_theme.dart';
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
      String? transcription;
      String? pronunciationUrl;
      String? example;
      final singleWord = english.split(RegExp(r'\s+')).length == 1;
      if (singleWord) {
        try {
          final enrich = await api.enrichWord(english);
          if (enrich.senses.isNotEmpty) {
            transcription = enrich.transcription;
            pronunciationUrl = enrich.pronunciationUrl;
            example = enrich.senses.first.example.isEmpty ? null : enrich.senses.first.example;
          }
        } catch (_) {}
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
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loading ? null : _addToDeck,
                icon: const Icon(Icons.add_card),
                label: const Text('Добавить в колоду'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
