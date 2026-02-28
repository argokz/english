import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../providers/youtube_provider.dart';
import '../api/api_client.dart';
import '../widgets/youtube_search_dialog.dart';

class IeltsListeningScreen extends StatefulWidget {
  const IeltsListeningScreen({super.key});

  @override
  State<IeltsListeningScreen> createState() => _IeltsListeningScreenState();
}

class _IeltsListeningScreenState extends State<IeltsListeningScreen>
    with SingleTickerProviderStateMixin {
  final _urlController = TextEditingController();
  YoutubePlayerController? _playerController;
  late TabController _tabController;

  // Chat state
  final _chatController = TextEditingController();
  final _chatScrollController = ScrollController();
  final List<_ChatMessage> _chatMessages = [];
  bool _isChatLoading = false;

  static const _tabs = ['Настройки', 'Транскрипция', 'Перевод', 'Вопросы', 'Чат'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<YoutubeProvider>().fetchHistory();
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _playerController?.dispose();
    _chatController.dispose();
    _chatScrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _initPlayer(String videoId) {
    if (_playerController != null) {
      _playerController!.load(videoId);
    } else {
      _playerController = YoutubePlayerController(
        initialVideoId: videoId,
        flags: const YoutubePlayerFlags(autoPlay: false, mute: false),
      );
    }
  }

  void _processVideo() async {
    final provider = context.read<YoutubeProvider>();
    final url = _urlController.text.trim();
    if (url.isNotEmpty) {
      final parsedId = YoutubePlayer.convertUrlToId(url);
      if (parsedId != null) {
        setState(() => _initPlayer(parsedId));
      }
    }

    await provider.processVideo(url: url.isEmpty ? null : url);

    if (!mounted) return;
    if (url.isEmpty && provider.currentVideo != null) {
      final parsedId = YoutubePlayer.convertUrlToId(provider.currentVideo!.url);
      if (parsedId != null) {
        setState(() => _initPlayer(parsedId));
      }
    }
    // Auto-switch to transcription tab after load
    if (provider.currentVideo != null) {
      _tabController.animateTo(1);
    }
  }

  void _loadFromHistory(YouTubeHistoryItem item) {
    final provider = context.read<YoutubeProvider>();
    provider.selectVideoFromHistory(item);
    final parsedId = YoutubePlayer.convertUrlToId(item.url);
    if (parsedId != null) {
      setState(() => _initPlayer(parsedId));
    }
    _tabController.animateTo(1);
  }

  Future<void> _sendChatMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    final provider = context.read<YoutubeProvider>();
    final videoId = provider.currentVideo?.id;
    if (videoId == null) return;

    setState(() {
      _chatMessages.add(_ChatMessage(text: text, isUser: true));
      _chatController.clear();
      _isChatLoading = true;
    });
    _scrollChatToBottom();

    final answer = await provider.askQuestion(videoId, text);
    if (!mounted) return;
    setState(() {
      _chatMessages.add(_ChatMessage(text: answer, isUser: false));
      _isChatLoading = false;
    });
    _scrollChatToBottom();
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ─── Setup Tab ───────────────────────────────────────────────────────────

  Widget _buildSetupTab(YoutubeProvider provider) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: 'YouTube URL (оставьте пустым для автоподбора)',
                border: const OutlineInputBorder(),
                hintText: 'https://youtube.com/watch?v=...',
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_urlController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _urlController.clear();
                          FocusScope.of(context).unfocus();
                          setState(() {});
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.search),
                      tooltip: 'Поиск видео по названию',
                      onPressed: () async {
                        FocusScope.of(context).unfocus();
                        final url = await YoutubeSearchDialog.show(context);
                        if (url != null && url.isNotEmpty) {
                          _urlController.text = url;
                          _processVideo();
                        }
                      },
                    ),
                  ],
                ),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: provider.isProcessing ? null : _processVideo,
              icon: provider.isProcessing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_circle_filled),
              label: Text(provider.isProcessing
                  ? 'Загрузка и транскрибация...'
                  : 'Начать занятие'),
            ),
            if (provider.processingError != null) ...[
              const SizedBox(height: 8),
              Text(provider.processingError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 24),
            Text('История', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (provider.isLoadingHistory)
              const Center(child: CircularProgressIndicator())
            else if (provider.history.isEmpty)
              const Text('История пуста.')
            else
              ...provider.history.map((h) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.play_circle_fill),
                      title: Text(
                        h.videoId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        'Просмотрено: ${h.viewedAt.toLocal().toString().split('.')[0]}',
                      ),
                      onTap: () => _loadFromHistory(h),
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  // ─── Transcription Tab ────────────────────────────────────────────────────

  Widget _buildTranscriptionTab(YoutubeProvider provider) {
    if (provider.isProcessing && provider.currentVideo == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Видео загружается и транскрибируется…\nЭто может занять от 2 до 30 минут.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    if (provider.currentVideo == null) {
      return const Center(child: Text('Сначала выберите или найдите видео.'));
    }

    final text = provider.currentVideo!.transcription;
    final paragraphs = _splitIntoParagraphs(text);

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: paragraphs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return _TranscriptParagraph(
          index: index + 1,
          text: paragraphs[index],
        );
      },
    );
  }

  // ─── Translation Tab ──────────────────────────────────────────────────────

  Widget _buildTranslationTab(YoutubeProvider provider) {
    if (provider.isProcessing && provider.currentVideo == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.currentVideo == null) {
      return const Center(child: Text('Сначала выберите или найдите видео.'));
    }

    final translation = provider.currentVideo!.translation;
    if (translation.isEmpty) {
      return const Center(
        child: Text(
          'Перевод недоступен для этого видео.\n(Перевод генерируется только при новой обработке видео.)',
          textAlign: TextAlign.center,
        ),
      );
    }

    final paragraphs = _splitIntoParagraphs(translation);

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: paragraphs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return _TranscriptParagraph(
          index: index + 1,
          text: paragraphs[index],
          accentColor: Theme.of(context).colorScheme.tertiary,
        );
      },
    );
  }

  // ─── Questions Tab ────────────────────────────────────────────────────────

  Widget _buildQuestionsTab(YoutubeProvider provider) {
    if (provider.isProcessing && provider.currentVideo == null) {
      return const Center(child: Text('Дождитесь окончания транскрибации…'));
    }
    if (provider.currentVideo == null) {
      return const Center(child: Text('Сначала выберите или найдите видео.'));
    }
    if (provider.isLoadingQuestions) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Генерируем вопросы и fill-in-the-gaps…'),
          ],
        ),
      );
    }
    if (provider.questionsError != null) {
      return Center(child: Text(provider.questionsError!));
    }
    final qResult = provider.questions;
    if (qResult == null ||
        (qResult.questions.isEmpty && qResult.gapFillQuestions.isEmpty)) {
      return const Center(child: Text('Вопросы не найдены.'));
    }

    // Build a flat list of widgets with stable keys
    final items = <Widget>[
      if (qResult.questions.isNotEmpty)
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('Multiple Choice',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
      ...qResult.questions.map(
        (q) => _MultipleChoiceCard(key: ValueKey('mc_${q.question}'), question: q),
      ),
      if (qResult.gapFillQuestions.isNotEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 16, bottom: 8),
          child: Text('Fill in the gaps',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
      ...qResult.gapFillQuestions.map(
        (g) => _GapFillCard(key: ValueKey('gap_${g.sentence}'), question: g),
      ),
    ];

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      // Use keys so Flutter preserves state for each card while scrolling
      itemCount: items.length,
      itemBuilder: (context, index) => items[index],
    );
  }

  // ─── Chat Tab ─────────────────────────────────────────────────────────────

  Widget _buildChatTab(YoutubeProvider provider) {
    if (provider.currentVideo == null) {
      return const Center(child: Text('Сначала выберите или найдите видео.'));
    }

    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        // Hint strip
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: cs.surfaceContainerHighest,
          child: Text(
            'Задайте вопрос по содержанию видео: краткий пересказ, объяснение идей, перевод фрагментов…',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        // Chat messages
        Expanded(
          child: _chatMessages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline,
                          size: 48, color: cs.outline),
                      const SizedBox(height: 12),
                      Text(
                        'Начните диалог!\nНапример: "Сделай краткий пересказ"',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.outline),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _chatScrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount:
                      _chatMessages.length + (_isChatLoading ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _chatMessages.length && _isChatLoading) {
                      return const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)),
                              SizedBox(width: 8),
                              Text('AI думает…',
                                  style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        ),
                      );
                    }
                    final msg = _chatMessages[index];
                    return _ChatBubble(message: msg);
                  },
                ),
        ),
        // Input area
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    decoration: const InputDecoration(
                      hintText: 'Ваш вопрос…',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    onSubmitted: (_) => _sendChatMessage(),
                    textInputAction: TextInputAction.send,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _isChatLoading ? null : _sendChatMessage,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.all(14),
                    minimumSize: const Size(48, 48),
                  ),
                  child: _isChatLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  List<String> _splitIntoParagraphs(String text) {
    // Split by newlines, then group sentences into blocks of ~150 chars
    final rawParagraphs =
        text.split(RegExp(r'\n+')).where((p) => p.trim().isNotEmpty).toList();
    if (rawParagraphs.length > 1) return rawParagraphs;

    // Single block: split by sentence endings into ~3-sentence groups
    final sentences =
        text.split(RegExp(r'(?<=[.!?])\s+')).where((s) => s.isNotEmpty).toList();
    if (sentences.length <= 3) return [text];
    final groups = <String>[];
    for (var i = 0; i < sentences.length; i += 3) {
      groups.add(sentences
          .sublist(i, i + 3 > sentences.length ? sentences.length : i + 3)
          .join(' '));
    }
    return groups;
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<YoutubeProvider>();

    return OrientationBuilder(
      builder: (context, orientation) {
        final isLandscape = orientation == Orientation.landscape;

        final tabBar = TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: _tabs.map((t) => Tab(text: t)).toList(),
        );

        final tabBarView = TabBarView(
          controller: _tabController,
          children: [
            _buildSetupTab(provider),
            _buildTranscriptionTab(provider),
            _buildTranslationTab(provider),
            _buildQuestionsTab(provider),
            _buildChatTab(provider),
          ],
        );

        final youtubePlayer = _playerController != null
            ? YoutubePlayer(
                controller: _playerController!,
                showVideoProgressIndicator: true,
                progressIndicatorColor: Colors.red,
                onEnded: (_) {},
              )
            : null;

        if (isLandscape && youtubePlayer != null) {
          // ── Landscape: player left, tabs right ──
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  // Player takes ~55% width
                  Flexible(
                    flex: 55,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [youtubePlayer],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  // Tabs take ~45% width
                  Flexible(
                    flex: 45,
                    child: Column(
                      children: [
                        tabBar,
                        Expanded(child: tabBarView),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // ── Portrait: standard layout ──
        return Scaffold(
          appBar: AppBar(
            title: const Text('IELTS Listening'),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: tabBar,
            ),
          ),
          body: Column(
            children: [
              if (youtubePlayer != null) youtubePlayer,
              Expanded(child: tabBarView),
            ],
          ),
        );
      },
    );
  }
}

// ─── Transcript Paragraph ─────────────────────────────────────────────────────

class _TranscriptParagraph extends StatelessWidget {
  final int index;
  final String text;
  final Color? accentColor;

  const _TranscriptParagraph({
    required this.index,
    required this.text,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = accentColor ?? cs.primary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: accent.withOpacity(0.5), width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            margin: const EdgeInsets.only(right: 10, top: 1),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$index',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.bold, color: accent),
            ),
          ),
          Expanded(
            child: SelectableText(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(height: 1.6, fontSize: 15.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Chat Bubble ─────────────────────────────────────────────────────────────

class _ChatMessage {
  final String text;
  final bool isUser;
  _ChatMessage({required this.text, required this.isUser});
}

class _ChatBubble extends StatelessWidget {
  final _ChatMessage message;
  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isUser = message.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isUser ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: SelectableText(
          message.text,
          style: TextStyle(
            color: isUser ? cs.onPrimary : cs.onSurface,
            height: 1.45,
            fontSize: 14.5,
          ),
        ),
      ),
    );
  }
}

// ─── Multiple Choice Card ────────────────────────────────────────────────────

class _MultipleChoiceCard extends StatefulWidget {
  final YouTubeQuestion question;
  const _MultipleChoiceCard({super.key, required this.question});

  @override
  State<_MultipleChoiceCard> createState() => _MultipleChoiceCardState();
}

class _MultipleChoiceCardState extends State<_MultipleChoiceCard> {
  String? _selectedOption;

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final isAnswered = _selectedOption != null;
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(q.question,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            ...q.options.map((opt) {
              final isCorrect = opt == q.correctAnswer;
              final isSelected = opt == _selectedOption;

              Color? bgColor;
              if (isAnswered) {
                if (isCorrect) bgColor = Colors.green.withOpacity(0.15);
                else if (isSelected) bgColor = Colors.red.withOpacity(0.15);
              }

              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: isAnswered
                    ? null
                    : () => setState(() => _selectedOption = opt),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isAnswered && isCorrect
                          ? Colors.green
                          : isAnswered && isSelected
                              ? Colors.red
                              : cs.outlineVariant,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isAnswered && isCorrect
                            ? Icons.check_circle
                            : isSelected
                                ? Icons.cancel
                                : Icons.circle_outlined,
                        color: isAnswered && isCorrect
                            ? Colors.green
                            : isSelected
                                ? Colors.red
                                : cs.outline,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(opt)),
                    ],
                  ),
                ),
              );
            }),
            if (isAnswered) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('💡 ${q.explanation}',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Gap Fill Card ────────────────────────────────────────────────────────────

class _GapFillCard extends StatefulWidget {
  final YouTubeGapQuestion question;
  const _GapFillCard({super.key, required this.question});

  @override
  State<_GapFillCard> createState() => _GapFillCardState();
}

class _GapFillCardState extends State<_GapFillCard> {
  final _controller = TextEditingController();
  bool _isChecked = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.question;
    final parts = g.sentence.split('___');
    final isCorrect =
        _controller.text.trim().toLowerCase() == g.answer.trim().toLowerCase();

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (parts.isNotEmpty)
                  Text(parts[0], style: const TextStyle(fontSize: 15.5)),
                Container(
                  width: 130,
                  margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: TextField(
                    controller: _controller,
                    enabled: !_isChecked,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 9),
                      filled: true,
                      fillColor: _isChecked
                          ? (isCorrect
                              ? Colors.green.withOpacity(0.12)
                              : Colors.red.withOpacity(0.12))
                          : null,
                      border: const OutlineInputBorder(),
                      focusedBorder: const OutlineInputBorder(
                          borderSide:
                              BorderSide(color: Colors.blue, width: 1.5)),
                    ),
                    onSubmitted: (_) {
                      setState(() => _isChecked = true);
                    },
                    textInputAction: TextInputAction.done,
                  ),
                ),
                if (parts.length > 1)
                  Text(parts[1], style: const TextStyle(fontSize: 15.5)),
              ],
            ),
            const SizedBox(height: 12),
            if (!_isChecked)
              ElevatedButton(
                onPressed: () => setState(() => _isChecked = true),
                child: const Text('Проверить'),
              ),
            if (_isChecked) ...[
              Row(
                children: [
                  Icon(isCorrect ? Icons.check_circle : Icons.cancel,
                      color: isCorrect ? Colors.green : Colors.red),
                  const SizedBox(width: 8),
                  if (!isCorrect)
                    Expanded(
                      child: Text('Правильно: ${g.answer}',
                          style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold)),
                    )
                  else
                    const Text('Верно! 🎉',
                        style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold)),
                ],
              ),
              if (g.explanation.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(g.explanation,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
