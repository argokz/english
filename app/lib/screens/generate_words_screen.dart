import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

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
    setState(() => _loading = true);
    try {
      final created = await context.read<AuthProvider>().api.generateWords(
            deckId: widget.deckId,
            level: _topic.trim().isEmpty ? _level : null,
            topic: _topic.trim().isEmpty ? null : _topic.trim(),
            count: _count,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Добавлено карточек: $created')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Сгенерировать слова')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Уровень CEFR'),
            DropdownButton<String>(
              value: _level,
              items: levels.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
              onChanged: (v) => setState(() => _level = v),
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Или тема (напр. бизнес, путешествия)',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _topic = v),
            ),
            const SizedBox(height: 16),
            Text('Количество: $_count'),
            Slider(value: _count.toDouble(), min: 5, max: 50, divisions: 9, label: '$_count', onChanged: (v) => setState(() => _count = v.round())),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _loading ? null : _generate,
              child: _loading ? const SizedBox(height: 24, child: Center(child: CircularProgressIndicator(strokeWidth: 2))) : const Text('Сгенерировать'),
            ),
          ],
        ),
      ),
    );
  }
}
