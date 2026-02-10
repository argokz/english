import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Добавить слово')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _wordController,
                      decoration: const InputDecoration(labelText: 'Слово (англ.)', border: OutlineInputBorder()),
                      textCapitalization: TextCapitalization.none,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.volume_up),
                    onPressed: _playWord,
                    tooltip: 'Произношение',
                  ),
                ],
              ),
              if (_transcription != null && _transcription!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text('Транскрипция: ', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                    Text('/$_transcription/', style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 16)),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _translationController,
                      decoration: const InputDecoration(labelText: 'Перевод', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: _enriching ? null : _enrich,
                    child: _enriching ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Подсказать'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _exampleController,
                decoration: const InputDecoration(labelText: 'Пример (необяз.)', border: OutlineInputBorder()),
                maxLines: 2,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _loading ? null : _save,
                child: _loading ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Сохранить'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
