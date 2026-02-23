import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../providers/youtube_provider.dart';
import '../api/api_client.dart';

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
    final success = await provider.processVideo(url: url.isEmpty ? null : url);
    if (success && provider.currentVideo != null && mounted) {
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
            decoration: const InputDecoration(
              labelText: 'YouTube URL (оставьте пустым для автоподбора)',
              border: OutlineInputBorder(),
              hintText: 'https://youtube.com/watch?v=...',
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
    if (provider.currentVideo == null) {
      return const Center(child: Text('Сначала выберите или найдите видео.'));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        provider.currentVideo!.transcription,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
      ),
    );
  }

  Widget _buildQuestionsTab(YoutubeProvider provider) {
    if (provider.currentVideo == null) {
      return const Center(child: Text('Сначала выберите или найдите видео.'));
    }
    if (provider.isLoadingQuestions) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.questionsError != null) {
      return Center(child: Text(provider.questionsError!));
    }
    final qResult = provider.questions;
    if (qResult == null || qResult.questions.isEmpty) {
      return const Center(child: Text('Вопросы не найдены или еще генерируются.'));
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: qResult.questions.length,
      itemBuilder: (context, index) {
        final q = qResult.questions[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Q${index + 1}: ${q.question}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                ...q.options.map((opt) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        opt == q.correctAnswer ? Icons.check_circle : Icons.circle_outlined,
                        color: opt == q.correctAnswer ? Colors.green : Colors.grey,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(opt)),
                    ],
                  ),
                )),
                const SizedBox(height: 8),
                Text('Explanation: ${q.explanation}', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
              ],
            ),
          ),
        );
      },
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
