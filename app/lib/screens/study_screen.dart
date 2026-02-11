import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_theme.dart';
import '../core/pos_colors.dart';
import '../models/card.dart' as app;
import '../models/study_mode.dart';
import '../providers/auth_provider.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_overlay.dart';

class StudyScreen extends StatefulWidget {
  const StudyScreen({super.key, required this.deckId, required this.deckName});

  final String deckId;
  final String deckName;

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  List<app.CardModel>? _queue;
  int _index = 0;
  bool _showAnswer = false;
  bool _loading = true;
  String? _error;
  StudyMode _studyMode = StudyMode.englishToRussian;
  final TextEditingController _answerController = TextEditingController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isCorrect = false;
  bool _checkingAnswer = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _load();
    _answerController.addListener(() {
      setState(() {}); // Обновляем UI при изменении текста
    });
  }

  @override
  void dispose() {
    _answerController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final modeKey = prefs.getString('study_mode') ?? 'english_to_russian';
    setState(() {
      _studyMode = StudyModeExtension.fromStorageKey(modeKey);
    });
  }

  StudyMode _getCurrentCardMode() {
    if (_studyMode == StudyMode.mixed) {
      return Random().nextBool() ? StudyMode.englishToRussian : StudyMode.russianToEnglish;
    }
    return _studyMode;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<AuthProvider>().api;
      final due = await api.getDueCards(widget.deckId);
      setState(() {
        _queue = due;
        _index = 0;
        _showAnswer = false;
        _answerController.clear();
        _isCorrect = false;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _checkAnswer() async {
    if (_queue == null || _index >= _queue!.length) return;
    
    final card = _queue![_index];
    final currentMode = _getCurrentCardMode();
    final userAnswer = _answerController.text.trim();
    
    setState(() => _checkingAnswer = true);
    
    // Проверка правописания (без учета регистра и лишних пробелов)
    String correctAnswer;
    if (currentMode == StudyMode.englishToRussian) {
      correctAnswer = card.translation.toLowerCase().trim();
    } else {
      correctAnswer = card.word.toLowerCase().trim();
    }
    
    final normalizedUserAnswer = userAnswer.toLowerCase().trim();
    final isCorrect = normalizedUserAnswer == correctAnswer;
    
    // Небольшая толерантность: убираем множественные пробелы
    final normalizedCorrect = correctAnswer.replaceAll(RegExp(r'\s+'), ' ');
    final normalizedUser = normalizedUserAnswer.replaceAll(RegExp(r'\s+'), ' ');
    final isCorrectTolerant = normalizedUser == normalizedCorrect || normalizedUserAnswer == correctAnswer;
    
    setState(() {
      _isCorrect = isCorrectTolerant;
      _showAnswer = true;
      _checkingAnswer = false;
    });
  }

  Future<void> _playPronunciation() async {
    final card = _queue![_index];
    if (card.pronunciationUrl != null && card.pronunciationUrl!.isNotEmpty) {
      try {
        await _audioPlayer.play(UrlSource(card.pronunciationUrl!));
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка воспроизведения: $e')),
          );
        }
      }
    } else {
      // Fallback: используем Google TTS через URL
      final word = card.word;
      final url = 'https://translate.google.com/translate_tts?ie=UTF-8&tl=en&client=tw-ob&q=${Uri.encodeComponent(word)}';
      try {
        await _audioPlayer.play(UrlSource(url));
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка воспроизведения: $e')),
          );
        }
      }
    }
  }

  Future<void> _rate(int rating) async {
    final card = _queue![_index];
    try {
      await context.read<AuthProvider>().api.reviewCard(card.id, rating);
      setState(() {
        _queue!.removeAt(_index);
        if (_queue!.isEmpty) _index = 0;
        _showAnswer = false;
        _answerController.clear();
        _isCorrect = false;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.deckName)),
        body: const LoadingOverlay(message: 'Загрузка карточек…'),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.deckName)),
        body: EmptyState(
          icon: Icons.error_outline,
          message: _error!,
          actionLabel: 'Повторить',
          onAction: _load,
        ),
      );
    }
    if (_queue == null || _queue!.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.deckName)),
        body: const EmptyState(
          icon: Icons.celebration,
          message: 'На сегодня карточек нет. Отлично!',
        ),
      );
    }
    final card = _queue![_index];
    final currentMode = _getCurrentCardMode();
    
    // Определяем, что показывать на лицевой стороне
    final frontText = currentMode == StudyMode.englishToRussian ? card.word : card.translation;
    final backText = currentMode == StudyMode.englishToRussian ? card.translation : card.word;
    final showTranscription = currentMode == StudyMode.englishToRussian && card.transcription != null;
    final posLabel = (currentMode == StudyMode.englishToRussian && card.partOfSpeech != null && card.partOfSpeech!.isNotEmpty)
        ? PosColors.labelFor(card.partOfSpeech)
        : null;
    final posColor = posLabel != null ? PosColors.colorFor(card.partOfSpeech) : null;

    return Scaffold(
      appBar: AppBar(title: Text('${widget.deckName} (осталось ${_queue!.length})')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              // Лицевая сторона карточки
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  side: posColor != null ? BorderSide(color: posColor!, width: 3) : BorderSide.none,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        frontText,
                        style: Theme.of(context).textTheme.headlineLarge,
                        textAlign: TextAlign.center,
                      ),
                      if (posLabel != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          '($posLabel)',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: posColor ?? Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      if (showTranscription && (card.transcription != null && card.transcription!.isNotEmpty)) ...[
                        const SizedBox(height: 8),
                        Text(
                          '/${card.transcription}/',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontStyle: FontStyle.italic,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                      if (currentMode == StudyMode.englishToRussian) ...[
                        const SizedBox(height: 12),
                        IconButton(
                          icon: const Icon(Icons.volume_up),
                          onPressed: _playPronunciation,
                          tooltip: 'Произношение',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Поле ввода ответа
              if (!_showAnswer) ...[
                TextField(
                  controller: _answerController,
                  decoration: InputDecoration(
                    labelText: currentMode == StudyMode.englishToRussian 
                        ? 'Введите перевод на русском' 
                        : 'Введите слово на английском',
                    border: const OutlineInputBorder(),
                    suffixIcon: _answerController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.check),
                            onPressed: _checkingAnswer ? null : _checkAnswer,
                          )
                        : null,
                  ),
                  textCapitalization: currentMode == StudyMode.englishToRussian 
                      ? TextCapitalization.none 
                      : TextCapitalization.none,
                  autofocus: true,
                  onSubmitted: (_) => _checkAnswer(),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _checkingAnswer || _answerController.text.trim().isEmpty 
                      ? null 
                      : _checkAnswer,
                  child: _checkingAnswer 
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Проверить'),
                ),
              ] else ...[
                // Обратная сторона - показываем правильный ответ
                Card(
                  color: _isCorrect ? Colors.green.shade50 : Colors.red.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_answerController.text.isNotEmpty) ...[
                          Text(
                            'Ваш ответ:',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _answerController.text,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: _isCorrect ? Colors.green.shade700 : Colors.red.shade700,
                              decoration: _isCorrect ? null : TextDecoration.lineThrough,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        const SizedBox(height: 16),
                        Text(
                          'Правильный ответ:',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          backText,
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: Colors.green.shade700,
                          ),
                        ),
                        if (currentMode == StudyMode.russianToEnglish && (card.transcription != null && card.transcription!.isNotEmpty)) ...[
                          const SizedBox(height: 8),
                          Text(
                            '/${card.transcription}/',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontStyle: FontStyle.italic,
                              color: Colors.grey[600],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.volume_up),
                            onPressed: _playPronunciation,
                            tooltip: 'Произношение',
                          ),
                        ],
                        if (card.example != null && card.example!.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            card.example!,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontStyle: FontStyle.italic,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Как вспомнили?'),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    FilledButton.tonal(
                      onPressed: () => _rate(1),
                      child: const Text('Забыл'),
                    ),
                    FilledButton.tonal(onPressed: () => _rate(2), child: const Text('Сложно')),
                    FilledButton(onPressed: () => _rate(3), child: const Text('Нормально')),
                    FilledButton(onPressed: () => _rate(4), child: const Text('Легко')),
                  ],
                ),
              ],
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
