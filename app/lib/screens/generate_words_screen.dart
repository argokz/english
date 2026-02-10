import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/loading_overlay.dart';

class GenerateWordsScreen extends StatefulWidget {
  const GenerateWordsScreen({super.key, required this.deckId});

  final String deckId;

  @override
  State<GenerateWordsScreen> createState() => _GenerateWordsScreenState();
}

class _GenerateWordsScreenState extends State<GenerateWordsScreen> {
  String? _level = 'A1';
  String _topic = '';
  int _count = 20;
  bool _loading = false;

  static const levels = ['A1', 'A2', 'B1', 'B2', 'C1'];

  Future<void> _generate() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final result = await context.read<AuthProvider>().api.generateWords(
            deckId: widget.deckId,
            level: _topic.trim().isEmpty ? _level : null,
            topic: _topic.trim().isEmpty ? null : _topic.trim(),
            count: _count,
          );
      if (mounted) {
        String msg = 'Добавлено карточек: ${result.created}';
        if (result.skippedDuplicates > 0) {
          msg += '. Пропущено (уже в колоде): ${result.skippedDuplicates}';
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            action: SnackBarAction(
              label: 'Повторить',
              onPressed: () => _generate(),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Сгенерировать слова')),
      body: _loading
          ? const LoadingOverlay(
              message: 'Генерация слов…',
              subtitle: 'Может занять 1–2 минуты',
            )
          : SingleChildScrollView(
              padding: AppTheme.paddingScreen,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: AppTheme.paddingCard,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Уровень CEFR', style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: _level,
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                            items: levels.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                            onChanged: (v) => setState(() => _level = v),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            decoration: const InputDecoration(
                              labelText: 'Или тема (напр. бизнес, путешествия)',
                            ),
                            onChanged: (v) => setState(() => _topic = v),
                          ),
                          const SizedBox(height: 20),
                          Text('Количество: $_count', style: Theme.of(context).textTheme.titleSmall),
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                            ),
                            child: Slider(
                              value: _count.toDouble(),
                              min: 5,
                              max: 50,
                              divisions: 9,
                              label: '$_count',
                              onChanged: (v) => setState(() => _count = v.round()),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _generate,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, AppTheme.buttonMinHeight + 8),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('Сгенерировать'),
                  ),
                ],
              ),
            ),
    );
  }
}
