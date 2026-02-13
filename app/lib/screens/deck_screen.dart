import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import '../api/api_client.dart';
import '../core/app_theme.dart';
import '../core/pos_colors.dart';
import '../models/card.dart' as app;
import '../providers/auth_provider.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_overlay.dart';
import 'add_word_screen.dart';
import 'bulk_add_words_screen.dart';
import 'generate_words_screen.dart';
import 'study_screen.dart';
import 'similar_words_screen.dart';

class DeckScreen extends StatefulWidget {
  const DeckScreen({super.key, required this.deckId, required this.deckName});

  final String deckId;
  final String deckName;

  @override
  State<DeckScreen> createState() => _DeckScreenState();
}

class _DeckScreenState extends State<DeckScreen> {
  List<app.CardModel>? _cards;
  bool _loading = true;
  String? _error;
  bool _groupBySynonyms = false;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';
  bool _selectionMode = false;
  final Set<String> _selectedWordKeys = {};

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _removeCardsFromList(Set<String> cardIds) {
    if (_cards == null || cardIds.isEmpty) return;
    setState(() {
      _cards = _cards!.where((c) => !cardIds.contains(c.id)).toList();
    });
  }

  void _replaceCardInList(app.CardModel updated) {
    if (_cards == null) return;
    final idx = _cards!.indexWhere((c) => c.id == updated.id);
    if (idx < 0) return;
    setState(() {
      _cards = [..._cards!.sublist(0, idx), updated, ..._cards!.sublist(idx + 1)];
    });
  }

  Future<void> _showExamplesForCard(app.CardModel card) async {
    List<String> examples = card.examples ?? [];
    if (examples.isEmpty) {
      try {
        final updated = await context.read<AuthProvider>().api.fetchCardExamples(widget.deckId, card.id);
        if (mounted) {
          _replaceCardInList(updated);
          examples = updated.examples ?? [];
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
        return;
      }
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Примеры: ${card.word}', style: Theme.of(ctx).textTheme.titleMedium),
            ),
            if (examples.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Text('Нет примеров'))
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.5),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: examples.length,
                  itemBuilder: (_, i) {
                    final ex = examples[i];
                    final sep = ex.indexOf(' — ');
                    return ListTile(
                      title: Text(sep >= 0 ? ex.substring(0, sep).trim() : ex, style: const TextStyle(fontSize: 14)),
                      subtitle: sep >= 0 ? Text(ex.substring(sep + 3).trim(), style: TextStyle(fontSize: 13, color: Theme.of(ctx).colorScheme.onSurfaceVariant)) : null,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<app.CardModel> _getFilteredCards() {
    final cards = _cards ?? [];
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return cards;
    return cards.where((c) {
      final word = (c.word).toLowerCase();
      final translation = (c.translation).toLowerCase();
      return word.contains(q) || translation.contains(q);
    }).toList();
  }

  Future<void> _playWord(app.CardModel card) async {
    try {
      if (card.pronunciationUrl != null && card.pronunciationUrl!.isNotEmpty) {
        await _audioPlayer.play(UrlSource(card.pronunciationUrl!));
      } else {
        final url = 'https://translate.google.com/translate_tts?ie=UTF-8&tl=en&client=tw-ob&q=${Uri.encodeComponent(card.word)}';
        await _audioPlayer.play(UrlSource(url));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка воспроизведения: $e')));
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _runBackfillTranscriptions() async {
    final api = context.read<AuthProvider>().api;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const LoadingOverlay(
        message: 'Запуск обновления транскрипций…',
        subtitle: 'Обработка идёт в фоне',
      ),
    );
    try {
      final message = await api.backfillTranscriptions(deckId: widget.deckId);
      if (mounted) {
        Navigator.of(context).pop(); // Закрываем диалог загрузки
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Обновить',
              onPressed: () => _load(),
            ),
          ),
        );
        // Не вызываем _load() сразу, чтобы избежать таймаута
        // Пользователь может обновить вручную через кнопку в SnackBar
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Закрываем диалог загрузки
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            action: SnackBarAction(label: 'Повторить', onPressed: () => _runBackfillTranscriptions()),
          ),
        );
      }
    }
  }

  Future<void> _runBackfillPos() async {
    final api = context.read<AuthProvider>().api;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const LoadingOverlay(
        message: 'Запуск обновления…',
        subtitle: 'Обработка идёт в фоне',
      ),
    );
    try {
      final message = await api.backfillPos(widget.deckId);
      if (mounted) {
        Navigator.of(context).pop(); // Закрываем диалог загрузки
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Обновить',
              onPressed: () => _load(),
            ),
          ),
        );
        // Не вызываем _load() сразу, чтобы избежать таймаута
        // Пользователь может обновить вручную через кнопку в SnackBar
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Закрываем диалог загрузки
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            action: SnackBarAction(label: 'Повторить', onPressed: () => _runBackfillPos()),
          ),
        );
      }
    }
  }

  Future<void> _runRemoveDuplicates() async {
    try {
      final removed = await context.read<AuthProvider>().api.removeDuplicates(widget.deckId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(removed > 0 ? 'Удалено дубликатов: $removed' : 'Дубликатов нет')),
        );
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  Future<void> _showSuggestSynonymGroups() async {
    final api = context.read<AuthProvider>().api;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const LoadingOverlay(
        message: 'Поиск групп синонимов…',
        subtitle: 'Может занять 1–2 минуты',
      ),
    );
    List<SynonymGroup>? suggested;
    try {
      suggested = await api.suggestSynonymGroups(widget.deckId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), action: SnackBarAction(label: 'Повторить', onPressed: () => _showSuggestSynonymGroups())),
        );
      }
      return;
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
    if (suggested == null || suggested.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Группы синонимов не найдены')),
      );
      return;
    }
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Предложенные группы синонимов'),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: suggested!.length,
            itemBuilder: (_, i) {
              final g = suggested![i];
              return ListTile(
                title: Text(g.words.join(', ')),
                subtitle: Text('${g.cardIds.length} карточек'),
              );
            },
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await api.applySynonymGroups(widget.deckId, suggested!.map((g) => g.cardIds).toList());
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Применено групп: ${suggested!.length}')),
                  );
                  setState(() => _groupBySynonyms = true);
                  _load();
                }
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
              }
            },
            child: const Text('Применить'),
          ),
        ],
      ),
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<AuthProvider>().api;
      final cards = await api.getCards(widget.deckId);
      setState(() {
        _cards = cards;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectionMode ? 'Выбрано: ${_selectedWordKeys.length}' : widget.deckName),
        actions: [
          if (_selectionMode) ...[
            TextButton(
              onPressed: () => setState(() {
                _selectionMode = false;
                _selectedWordKeys.clear();
              }),
              child: const Text('Отмена'),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _selectedWordKeys.isEmpty ? null : _deleteSelectedGroups,
              tooltip: 'Удалить выбранные',
            ),
          ] else ...[
            if (!_groupBySynonyms)
              IconButton(
                icon: const Icon(Icons.playlist_remove),
                onPressed: () => setState(() => _selectionMode = true),
                tooltip: 'Множественное удаление',
              ),
            IconButton(
              icon: const Icon(Icons.school),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StudyScreen(deckId: widget.deckId, deckName: widget.deckName),
                ),
              ),
            ),
            PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              if (value == 'backfill') _runBackfillTranscriptions();
              else if (value == 'backfill_pos') _runBackfillPos();
              else if (value == 'remove_duplicates') _runRemoveDuplicates();
              else if (value == 'synonym_groups') _showSuggestSynonymGroups();
              else if (value == 'bulk_add') {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BulkAddWordsScreen(deckId: widget.deckId),
                  ),
                );
                _load();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'bulk_add', child: Text('Добавить несколько слов')),
              const PopupMenuItem(value: 'backfill_pos', child: Text('Обновить переводы по частям речи')),
              const PopupMenuItem(value: 'backfill', child: Text('Обновить транскрипции')),
              const PopupMenuItem(value: 'synonym_groups', child: Text('Найти группы синонимов')),
              const PopupMenuItem(value: 'remove_duplicates', child: Text('Удалить дубликаты слов')),
            ],
          ),
          ],
        ],
      ),
      body: _loading
          ? const LoadingOverlay(message: 'Загрузка колоды…')
          : _error != null
              ? EmptyState(
                  icon: Icons.error_outline,
                  message: _error!,
                  actionLabel: 'Повторить',
                  onAction: _load,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Поиск по слову или переводу',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchQuery.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  ),
                          ),
                          onChanged: (v) => setState(() => _searchQuery = v),
                        ),
                      ),
                      if ((_cards ?? []).any((c) => c.synonymGroupId != null)) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Row(
                            children: [
                              const Text('Группы синонимов: '),
                              ChoiceChip(
                                label: const Text('Все'),
                                selected: !_groupBySynonyms,
                                onSelected: (_) => setState(() => _groupBySynonyms = false),
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: const Text('По группам'),
                                selected: _groupBySynonyms,
                                onSelected: (_) => setState(() {
                                  _groupBySynonyms = true;
                                  _selectionMode = false;
                                  _selectedWordKeys.clear();
                                }),
                              ),
                            ],
                          ),
                        ),
                      ],
                      Expanded(
                        child: _groupBySynonyms ? _buildGroupedList() : _buildFlatList(),
                      ),
                    ],
                  ),
                ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FloatingActionButton.extended(
              heroTag: 'add',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AddWordScreen(deckId: widget.deckId),
                ),
              );
              _load();
            },
            icon: const Icon(Icons.add),
            label: const Text('Добавить слово'),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: 'generate',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GenerateWordsScreen(deckId: widget.deckId),
                ),
              );
              _load();
            },
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Сгенерировать слова'),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: 'similar',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SimilarWordsScreen(deckId: widget.deckId, deckName: widget.deckName),
                ),
              );
              _load();
            },
            icon: const Icon(Icons.lightbulb_outline),
            label: const Text('Похожие слова'),
          ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardTile(app.CardModel c) {
    final posLabel = c.partOfSpeech != null && c.partOfSpeech!.isNotEmpty
        ? PosColors.labelFor(c.partOfSpeech)
        : null;
    final posColor = posLabel != null ? PosColors.colorFor(c.partOfSpeech) : null;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        title: Text(c.word),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (posLabel != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Chip(
                  label: Text(posLabel, style: const TextStyle(fontSize: 12)),
                  backgroundColor: posColor!.withValues(alpha: 0.2),
                  side: BorderSide(color: posColor),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            Text(c.translation),
            if (c.transcription != null && c.transcription!.isNotEmpty)
              Text('/${c.transcription}/', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey[600])),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: InkWell(
                onTap: () => _showExamplesForCard(c),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    (c.examples != null && c.examples!.isNotEmpty) ? 'Примеры (${c.examples!.length})' : 'Запросить примеры',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.primary),
                  ),
                ),
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.volume_up, size: 22),
              onPressed: () => _playWord(c),
              tooltip: 'Произношение',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                try {
                  await context.read<AuthProvider>().api.deleteCard(c.id);
                  if (mounted) _removeCardsFromList({c.id});
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Group cards by word (case-insensitive). One row per word with all translations and POS chips.
  static Map<String, List<app.CardModel>> _groupByWord(List<app.CardModel> cards) {
    final map = <String, List<app.CardModel>>{};
    for (final c in cards) {
      final w = (c.word).trim().toLowerCase();
      if (w.isEmpty) continue;
      map.putIfAbsent(w, () => []).add(c);
    }
    for (final list in map.values) {
      list.sort((a, b) => (a.partOfSpeech ?? '').compareTo(b.partOfSpeech ?? ''));
    }
    return map;
  }

  Future<void> _deleteWordGroup(List<app.CardModel> groupCards) async {
    final ids = groupCards.map((c) => c.id).toSet();
    try {
      for (final c in groupCards) {
        await context.read<AuthProvider>().api.deleteCard(c.id);
      }
      if (mounted) _removeCardsFromList(ids);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  Future<void> _deleteSelectedGroups() async {
    if (_selectedWordKeys.isEmpty || _cards == null) return;
    final byWord = _groupByWord(_getFilteredCards());
    final toDelete = <app.CardModel>[];
    for (final key in _selectedWordKeys) {
      final group = byWord[key];
      if (group != null) toDelete.addAll(group);
    }
    final ids = toDelete.map((c) => c.id).toSet();
    try {
      for (final c in toDelete) {
        await context.read<AuthProvider>().api.deleteCard(c.id);
      }
      if (mounted) {
        setState(() {
          _selectedWordKeys.clear();
          _selectionMode = false;
        });
        _removeCardsFromList(ids);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Удалено: ${toDelete.length}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  Widget _buildWordGroupTile(String wordKey, List<app.CardModel> groupCards) {
    final first = groupCards.first;
    final word = first.word;
    final isSelected = _selectedWordKeys.contains(wordKey);
    String? transcription;
    for (final c in groupCards) {
      if (c.transcription != null && c.transcription!.isNotEmpty) {
        transcription = c.transcription;
        break;
      }
    }
    transcription ??= first.transcription;
    app.CardModel? cardForPlay;
    for (final c in groupCards) {
      if (c.pronunciationUrl != null && c.pronunciationUrl!.isNotEmpty) {
        cardForPlay = c;
        break;
      }
    }
    cardForPlay ??= first;
    Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (_selectionMode)
                Checkbox(
                  value: isSelected,
                  onChanged: (_) => setState(() {
                    if (isSelected) _selectedWordKeys.remove(wordKey);
                    else _selectedWordKeys.add(wordKey);
                  }),
                ),
              Expanded(
                child: Text(
                  word,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (!_selectionMode) ...[
                IconButton(
                  icon: const Icon(Icons.volume_up, size: 22),
                  onPressed: () => _playWord(cardForPlay!),
                  tooltip: 'Произношение',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _deleteWordGroup(groupCards),
                  tooltip: 'Удалить слово',
                ),
              ],
            ],
          ),
            if (transcription != null && transcription.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('/$transcription/', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic, color: Colors.grey[600])),
              ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in groupCards) ...[
                Chip(
                  avatar: c.partOfSpeech != null && c.partOfSpeech!.isNotEmpty
                      ? CircleAvatar(backgroundColor: PosColors.colorFor(c.partOfSpeech), radius: 10)
                      : null,
                  label: Text(
                    c.partOfSpeech != null && c.partOfSpeech!.isNotEmpty
                        ? '${PosColors.labelFor(c.partOfSpeech)} ${c.translation}'
                        : c.translation,
                    style: const TextStyle(fontSize: 13),
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: InkWell(
              onTap: () => _showExamplesForCard(first),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  (first.examples != null && first.examples!.isNotEmpty)
                      ? 'Примеры (${first.examples!.length})'
                      : 'Запросить примеры',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.primary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (_selectionMode) {
      return Card(
        child: InkWell(
          onTap: () => setState(() {
            if (isSelected) _selectedWordKeys.remove(wordKey);
            else _selectedWordKeys.add(wordKey);
          }),
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          child: content,
        ),
      );
    }
    return Card(child: content);
  }

  Widget _buildFlatList() {
    final cards = _getFilteredCards();
    if (cards.isEmpty) {
      return EmptyState(
        icon: _searchQuery.isEmpty ? Icons.menu_book_outlined : Icons.search_off,
        message: _searchQuery.isEmpty ? 'Нет карточек в колоде' : 'Ничего не найдено по «$_searchQuery»',
      );
    }
    final byWord = _groupByWord(cards);
    final wordKeys = byWord.keys.toList()..sort((a, b) => a.compareTo(b));
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(8),
      itemCount: wordKeys.length,
      itemBuilder: (context, i) => _buildWordGroupTile(wordKeys[i], byWord[wordKeys[i]]!),
    );
  }

  Widget _buildGroupedList() {
    final cards = _getFilteredCards();
    if (cards.isEmpty) {
      return EmptyState(
        icon: _searchQuery.isEmpty ? Icons.menu_book_outlined : Icons.search_off,
        message: _searchQuery.isEmpty ? 'Нет карточек в колоде' : 'Ничего не найдено по «$_searchQuery»',
      );
    }
    final byGroup = <String?, List<app.CardModel>>{};
    for (final c in cards) {
      byGroup.putIfAbsent(c.synonymGroupId, () => []).add(c);
    }
    final groupOrder = byGroup.keys.toList()
      ..sort((a, b) {
        if (a == null) return 1;
        if (b == null) return -1;
        return a.compareTo(b);
      });
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(8),
      itemCount: groupOrder.length,
      itemBuilder: (context, gi) {
        final gid = groupOrder[gi];
        final groupCards = byGroup[gid]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(
                gid == null ? 'Без группы' : 'Синонимы: ${groupCards.map((c) => c.word).join(', ')}',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700], fontSize: 14),
              ),
            ),
            ...groupCards.map(_buildCardTile),
          ],
        );
      },
    );
  }
}
