import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../core/app_theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/loading_overlay.dart';

class IeltsWritingScreen extends StatefulWidget {
  const IeltsWritingScreen({super.key});

  @override
  State<IeltsWritingScreen> createState() => _IeltsWritingScreenState();
}

class _IeltsWritingScreenState extends State<IeltsWritingScreen> {
  final _textController = TextEditingController();
  int _timeLimitMinutes = 40;
  int _wordLimitMin = 250;
  int _wordLimitMax = 0; // 0 = не задано
  String _taskType = '';
  DateTime? _startTime;
  Timer? _timer;
  int _elapsedSeconds = 0;
  EvaluateWritingResult? _result;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _timer?.cancel();
    _textController.dispose();
    super.dispose();
  }

  int get _wordCount {
    return _textController.text.split(RegExp(r'\s+')).where((w) => w.trim().isNotEmpty).length;
  }

  void _startTimer() {
    if (_startTime != null) return;
    _startTime = DateTime.now();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final elapsed = DateTime.now().difference(_startTime!).inSeconds;
      if (_timeLimitMinutes > 0 && elapsed >= _timeLimitMinutes * 60) {
        _timer?.cancel();
      }
      setState(() => _elapsedSeconds = elapsed);
    });
    setState(() {});
  }

  String get _timerLabel {
    if (_timeLimitMinutes > 0) {
      final left = _timeLimitMinutes * 60 - _elapsedSeconds;
      if (left <= 0) return '0:00';
      final m = left ~/ 60;
      final s = left % 60;
      return '$m:${s.toString().padLeft(2, '0')}';
    }
    final m = _elapsedSeconds ~/ 60;
    final s = _elapsedSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _showSettings() async {
    final result = await showDialog<({int timeLimit, int wordMin, int wordMax, String task})>(
      context: context,
      builder: (ctx) => _SettingsDialog(
        timeLimitMinutes: _timeLimitMinutes,
        wordLimitMin: _wordLimitMin,
        wordLimitMax: _wordLimitMax,
        taskType: _taskType,
      ),
    );
    if (result != null) {
      setState(() {
        _timeLimitMinutes = result.timeLimit;
        _wordLimitMin = result.wordMin;
        _wordLimitMax = result.wordMax;
        _taskType = result.task;
      });
    }
  }

  Future<void> _submit() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите текст')));
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final res = await context.read<AuthProvider>().api.evaluateWriting(
            text: text,
            timeLimitMinutes: _timeLimitMinutes > 0 ? _timeLimitMinutes : null,
            timeUsedSeconds: _elapsedSeconds,
            wordLimitMin: _wordLimitMin > 0 ? _wordLimitMin : null,
            wordLimitMax: _wordLimitMax > 0 ? _wordLimitMax : null,
            taskType: _taskType.isEmpty ? null : _taskType,
          );
      if (mounted) setState(() { _result = res; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _reset() {
    _timer?.cancel();
    setState(() {
      _startTime = null;
      _elapsedSeconds = 0;
      _result = null;
      _error = null;
      _textController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IELTS Письмо'),
        actions: [
          IconButton(icon: const Icon(Icons.settings), onPressed: _showSettings, tooltip: 'Настройки'),
        ],
      ),
      body: _loading
          ? const LoadingOverlay(message: 'Проверка текста…', subtitle: 'Оценка и исправление ошибок')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Таймер и счётчик слов
                Material(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.timer_outlined, size: 22, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(_timerLabel, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                            if (_timeLimitMinutes > 0) Text(' осталось', style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                        Row(
                          children: [
                            Icon(Icons.text_fields, size: 22, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 8),
                            Text('$_wordCount слов', style: Theme.of(context).textTheme.titleMedium),
                            if (_wordLimitMin > 0) Text(' / $_wordLimitMin мин', style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: AppTheme.paddingScreen,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _textController,
                          maxLines: null,
                          minLines: 12,
                          decoration: const InputDecoration(
                            hintText: 'Напишите текст для проверки…\n\nНажмите здесь, чтобы начать — таймер запустится автоматически.',
                            alignLabelWithHint: true,
                          ),
                          onTap: _startTimer,
                          onChanged: (_) {
                            _startTimer();
                            setState(() {});
                          },
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            if (_result != null)
                              TextButton.icon(
                                icon: const Icon(Icons.refresh),
                                label: const Text('Новый текст'),
                                onPressed: _reset,
                              ),
                            const Spacer(),
                            FilledButton.icon(
                              onPressed: _submit,
                              icon: const Icon(Icons.check_circle_outline, size: 20),
                              label: const Text('Отправить на проверку'),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, AppTheme.buttonMinHeight),
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                              ),
                            ),
                          ],
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        ],
                        if (_result != null) ...[
                          const SizedBox(height: 24),
                          _buildResult(),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildResult() {
    final r = _result!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Результат: ${r.wordCount} слов${r.timeUsedSeconds != null ? ", время: ${r.timeUsedSeconds! ~/ 60}:${(r.timeUsedSeconds! % 60).toString().padLeft(2, '0')}" : ""}',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 12),
        _Section(title: 'Оценка', child: Text(r.evaluation)),
        if (r.correctedText.isNotEmpty) _Section(title: 'Исправленный текст', child: Text(r.correctedText)),
        if (r.errors.isNotEmpty) _Section(
          title: 'Ошибки (${r.errors.length})',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: r.errors.asMap().entries.map((e) {
              final err = e.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: Padding(
                    padding: AppTheme.paddingCard,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Chip(label: Text(err.type, style: const TextStyle(fontSize: 12))),
                            const SizedBox(width: 8),
                            Expanded(child: Text('«${err.original}» → ${err.correction}', style: const TextStyle(fontWeight: FontWeight.w500))),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(err.explanation, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        if (r.recommendations.isNotEmpty) _Section(title: 'Рекомендации', child: Text(r.recommendations)),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: AppTheme.paddingCard,
            child: child,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({
    required this.timeLimitMinutes,
    required this.wordLimitMin,
    required this.wordLimitMax,
    required this.taskType,
  });

  final int timeLimitMinutes;
  final int wordLimitMin;
  final int wordLimitMax;
  final String taskType;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final TextEditingController _timeController;
  late final TextEditingController _wordMinController;
  late final TextEditingController _wordMaxController;
  String _task = '';

  @override
  void initState() {
    super.initState();
    _timeController = TextEditingController(text: widget.timeLimitMinutes.toString());
    _wordMinController = TextEditingController(text: widget.wordLimitMin.toString());
    _wordMaxController = TextEditingController(text: widget.wordLimitMax > 0 ? widget.wordLimitMax.toString() : '');
    _task = widget.taskType;
  }

  @override
  void dispose() {
    _timeController.dispose();
    _wordMinController.dispose();
    _wordMaxController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Настройки'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Лимит времени (мин, 0 = без лимита)', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            TextField(
              controller: _timeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: '40'),
            ),
            const SizedBox(height: 16),
            Text('Мин. слов', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            TextField(
              controller: _wordMinController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: '250'),
            ),
            const SizedBox(height: 8),
            Text('Макс. слов (0 = не задано)', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            TextField(
              controller: _wordMaxController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'не задано'),
            ),
            const SizedBox(height: 16),
            Text('Тип задания', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            DropdownButtonFormField<String>(
              value: _task.isEmpty ? null : _task,
              decoration: const InputDecoration(),
              items: const [
                DropdownMenuItem(value: null, child: Text('Не указан')),
                DropdownMenuItem(value: 'task1', child: Text('Task 1')),
                DropdownMenuItem(value: 'task2', child: Text('Task 2')),
              ],
              onChanged: (v) => setState(() => _task = v ?? ''),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: () {
            Navigator.pop(context, (
              timeLimit: int.tryParse(_timeController.text) ?? 0,
              wordMin: int.tryParse(_wordMinController.text) ?? 0,
              wordMax: int.tryParse(_wordMaxController.text) ?? 0,
              task: _task,
            ));
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}
