import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import '../core/app_theme.dart';
import '../providers/auth_provider.dart';

class AddWordScreen extends StatefulWidget {
  const AddWordScreen({super.key, required this.deckId});

  final String deckId;

  @override
  State<AddWordScreen> createState() => _AddWordScreenState();
}

class _AddWordScreenState extends State<AddWordScreen> {
  final _wordController = TextEditingController();
  final _translationController = TextEditingController();
  final _exampleController = TextEditingController();
  bool _loading = false;
  bool _enriching = false;
  final AudioPlayer _audioPlayer = AudioPlayer();

  String? _transcription;
  String? _pronunciationUrl;

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _playWord() async {
    final word = _wordController.text.trim();
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
      final result = await context.read<AuthProvider>().api.enrichWord(word);
      if (mounted) {
        _translationController.text = result['translation'] ?? '';
        _exampleController.text = result['example'] ?? '';
        _transcription = result['transcription'];
        _pronunciationUrl = result['pronunciation_url'];
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка подсказки: $e')));
    } finally {
      if (mounted) setState(() => _enriching = false);
    }
  }

  Future<void> _save() async {
    final word = _wordController.text.trim();
    final translation = _translationController.text.trim();
    if (word.isEmpty || translation.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите слово и перевод')));
      return;
    }
    setState(() => _loading = true);
    try {
      await context.read<AuthProvider>().api.createCard(
            widget.deckId,
            word: word,
            translation: translation,
            example: _exampleController.text.trim().isEmpty ? null : _exampleController.text.trim(),
            transcription: _transcription,
            pronunciationUrl: _pronunciationUrl,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Сохранено')));
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
    return Scaffold(
      appBar: AppBar(title: const Text('Добавить слово')),
      body: SingleChildScrollView(
        padding: AppTheme.paddingScreen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _wordController,
                    decoration: const InputDecoration(
                      labelText: 'Слово (англ.)',
                      hintText: 'apple',
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
            if (_transcription != null && _transcription!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('Транскрипция: ', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  Text('/$_transcription/', style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontStyle: FontStyle.italic)),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _translationController,
                    decoration: const InputDecoration(labelText: 'Перевод', hintText: 'яблоко'),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonal(
                  onPressed: _enriching ? null : _enrich,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, AppTheme.buttonMinHeight)),
                  child: _enriching
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Подсказать'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _exampleController,
              decoration: const InputDecoration(
                labelText: 'Пример (необяз.)',
                alignLabelWithHint: true,
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _loading ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, AppTheme.buttonMinHeight + 8),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _loading
                  ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }
}
