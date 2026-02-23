import 'package:flutter/material.dart';
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

class _IeltsListeningScreenState extends State<IeltsListeningScreen> {
  final _urlController = TextEditingController();
  YoutubePlayerController? _playerController;
  final _questionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<YoutubeProvider>().fetchHistory();
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _playerController?.dispose();
    _questionController.dispose();
    super.dispose();
  }

  void _initPlayer(String videoId) {
    if (_playerController != null) {
      _playerController!.load(videoId);
    } else {
      _playerController = YoutubePlayerController(
        initialVideoId: videoId,
        flags: const YoutubePlayerFlags(
          autoPlay: false,
          mute: false,
        ),
      );
    }
  }

  void _processVideo() async {
    final provider = context.read<YoutubeProvider>();
    final url = _urlController.text.trim();
    if (url.isNotEmpty) {
      String? parsedId = YoutubePlayer.convertUrlToId(url);
      if (parsedId != null) {
        setState(() {
          _initPlayer(parsedId);
        });
      }
    }
    
    await provider.processVideo(url: url.isEmpty ? null : url);
    
    if (url.isEmpty && provider.currentVideo != null && mounted) {
      String? parsedId = YoutubePlayer.convertUrlToId(provider.currentVideo!.url);
      if (parsedId != null) {
        setState(() {
          _initPlayer(parsedId);
        });
      }
    }
  }

  void _loadFromHistory(YouTubeHistoryItem item) {
    final provider = context.read<YoutubeProvider>();
    provider.selectVideoFromHistory(item);
    String? parsedId = YoutubePlayer.convertUrlToId(item.url);
    if (parsedId != null) {
      setState(() {
        _initPlayer(parsedId);
      });
    }
  }

  Widget _buildSetupTab(YoutubeProvider provider) {
    return SingleChildScrollView(
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
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                tooltip: 'Поиск видео по названию',
                onPressed: () async {
                  final url = await YoutubeSearchDialog.show(context);
                  if (url != null && url.isNotEmpty) {
                    _urlController.text = url;
                    _processVideo();
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: provider.isProcessing ? null : _processVideo,
            icon: provider.isProcessing 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.search),
            label: Text(provider.isProcessing ? 'Поиск и транскрибация...' : 'Начать занятие'),
          ),
          if (provider.processingError != null) ...[
            const SizedBox(height: 8),
            Text(provider.processingError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
                title: Text(h.videoId),
                subtitle: Text('Просмотрено: ${h.viewedAt.toLocal().toString().split('.')[0]}'),
                trailing: const Icon(Icons.play_circle_fill),
                onTap: () => _loadFromHistory(h),
              ),
            )),
        ],
      ),
    );
  }

  Widget _buildTranscriptionTab(YoutubeProvider provider) {
    if (provider.isProcessing && provider.currentVideo == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Видео загружается и транскрибируется...\nЭто может занять от 2 до 30 минут.\nМожете заблокировать экран или начать смотреть видео — мы сообщим по завершении.',
                textAlign: TextAlign.center,
              )
            ],
          ),
        ),
      );
    }
    if (provider.currentVideo == null) {
      return const Center(child: Text('Сначала выберите или найдите видео.'));
    }
    
    final text = provider.currentVideo!.transcription;
    final paragraphs = text.split(RegExp(r'\n+')).where((p) => p.trim().isNotEmpty).toList();

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: paragraphs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SelectableText(
            paragraphs[index],
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
        );
      },
    );
  }

  Widget _buildQuestionsTab(YoutubeProvider provider) {
    if (provider.isProcessing && provider.currentVideo == null) {
      return const Center(child: Text('Дождитесь окончания транскрибации...'));
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
            Text('Генерируем вопросы и fill-in-the-gaps...')
          ]
        ),
      );
    }
    if (provider.questionsError != null) {
      return Center(child: Text(provider.questionsError!));
    }
    final qResult = provider.questions;
    if (qResult == null || (qResult.questions.isEmpty && qResult.gapFillQuestions.isEmpty)) {
      return const Center(child: Text('Вопросы не найдены или еще генерируются.'));
    }
    
    final items = [
      if (qResult.questions.isNotEmpty)
        const Padding(
          padding: EdgeInsets.only(bottom: 8.0),
          child: Text('Multiple Choice', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
      ...qResult.questions.map((q) => _MultipleChoiceCard(question: q)),
      
      if (qResult.gapFillQuestions.isNotEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 16.0, bottom: 8.0),
          child: Text('Fill in the gaps', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
      ...qResult.gapFillQuestions.map((g) => _GapFillCard(question: g)),
    ];

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) => items[index],
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<YoutubeProvider>();
    
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('IELTS Listening'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Настройки'),
              Tab(text: 'Транскрипция'),
              Tab(text: 'Вопросы'),
            ],
          ),
        ),
        body: Column(
          children: [
            if (_playerController != null)
              YoutubePlayer(
                controller: _playerController!,
                showVideoProgressIndicator: true,
                progressIndicatorColor: Colors.red,
              ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildSetupTab(provider),
                  _buildTranscriptionTab(provider),
                  _buildQuestionsTab(provider),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MultipleChoiceCard extends StatefulWidget {
  final YouTubeQuestion question;
  const _MultipleChoiceCard({required this.question});

  @override
  State<_MultipleChoiceCard> createState() => _MultipleChoiceCardState();
}

class _MultipleChoiceCardState extends State<_MultipleChoiceCard> {
  String? _selectedOption;

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final isAnswered = _selectedOption != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(q.question, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            ...q.options.map((opt) {
              final isCorrect = opt == q.correctAnswer;
              final isSelected = opt == _selectedOption;
              
              Color? bgColor;
              if (isAnswered) {
                if (isCorrect) bgColor = Colors.green.withOpacity(0.2);
                else if (isSelected) bgColor = Colors.red.withOpacity(0.2);
              }

              return InkWell(
                onTap: isAnswered ? null : () {
                  setState(() {
                    _selectedOption = opt;
                  });
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isAnswered && isCorrect ? Icons.check_circle : (isSelected ? Icons.cancel : Icons.circle_outlined),
                        color: isAnswered && isCorrect ? Colors.green : (isSelected ? Colors.red : Colors.grey),
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
                decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Text('Explanation: ${q.explanation}', style: Theme.of(context).textTheme.bodySmall),
              )
            ]
          ],
        ),
      ),
    );
  }
}

class _GapFillCard extends StatefulWidget {
  final YouTubeGapQuestion question;
  const _GapFillCard({required this.question});

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
    final isCorrect = _controller.text.trim().toLowerCase() == g.answer.toLowerCase();

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
                if (parts.isNotEmpty) Text(parts[0], style: const TextStyle(fontSize: 16)),
                Container(
                  width: 120,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  child: TextField(
                    controller: _controller,
                    enabled: !_isChecked,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                  ),
                ),
                if (parts.length > 1) Text(parts[1], style: const TextStyle(fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            if (!_isChecked)
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isChecked = true;
                  });
                },
                child: const Text('Check'),
              ),
            if (_isChecked) ...[
              Row(
                children: [
                  Icon(isCorrect ? Icons.check_circle : Icons.cancel, color: isCorrect ? Colors.green : Colors.red),
                  const SizedBox(width: 8),
                  if (!isCorrect) Text('Правильный ответ: ${g.answer}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  if (isCorrect) const Text('Верно!', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              Text(g.explanation, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
