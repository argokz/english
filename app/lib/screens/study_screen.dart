import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/card.dart' as app;
import '../providers/auth_provider.dart';

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
  bool _showBack = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
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
        _showBack = false;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _rate(int rating) async {
    final card = _queue![_index];
    try {
      await context.read<AuthProvider>().api.reviewCard(card.id, rating);
      setState(() {
        _queue!.removeAt(_index);
        if (_queue!.isEmpty) _index = 0;
        _showBack = false;
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
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.deckName)),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Повторить')),
            ],
          ),
        ),
      );
    }
    if (_queue == null || _queue!.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.deckName)),
        body: const Center(child: Text('На сегодня карточек нет. Отлично!')),
      );
    }
    final card = _queue![_index];
    return Scaffold(
      appBar: AppBar(title: Text('${widget.deckName} (осталось ${_queue!.length})')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _showBack = true),
                child: Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: _showBack
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(card.translation, style: Theme.of(context).textTheme.headlineMedium),
                                if (card.example != null && card.example!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 16),
                                    child: Text(card.example!, style: Theme.of(context).textTheme.bodyLarge),
                                  ),
                              ],
                            )
                          : Text(card.word, style: Theme.of(context).textTheme.headlineLarge),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              if (_showBack) ...[
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
            ],
          ),
        ),
      ),
    );
  }
}
