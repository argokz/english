import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../providers/youtube_provider.dart';
import '../api/api_client.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_overlay.dart';

class IeltsExamScreen extends StatefulWidget {
  const IeltsExamScreen({super.key});

  @override
  State<IeltsExamScreen> createState() => _IeltsExamScreenState();
}

class _IeltsExamScreenState extends State<IeltsExamScreen> {
  int _currentPartIndex = 0;
  bool _examStarted = false;
  Map<int, String> _userAnswers = {}; // Map of question index to answer string
  
  // Timing state
  Timer? _timer;
  int _secondsRemaining = 0;
  String _phase = 'idle'; // idle, pre_reading, playing, post_checking, finished

  YoutubePlayerController? _playerController;

  @override
  void dispose() {
    _timer?.cancel();
    _playerController?.dispose();
    super.dispose();
  }

  void _startExam(IeltsFullExamResponse exam) {
    setState(() {
      _examStarted = true;
      _currentPartIndex = 0;
      _userAnswers.clear();
      _startPart(exam.parts[0]);
    });
  }

  void _startPart(IeltsExamPartResponse part) {
    setState(() {
      _phase = 'pre_reading';
      _secondsRemaining = 30; // 30 seconds to read questions
    });
    
    String? videoId = YoutubePlayer.convertUrlToId(part.url) ?? part.videoId;
    _playerController?.dispose();
    _playerController = YoutubePlayerController(
      initialVideoId: videoId,
      flags: const YoutubePlayerFlags(
        autoPlay: false,
        mute: false,
        hideControls: true, // User cannot seek
        disableDragSeek: true,
      ),
    )..addListener(_playerListener);

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_secondsRemaining > 0) {
          _secondsRemaining--;
        } else {
          timer.cancel();
          if (_phase == 'pre_reading') {
            _startPlaying();
          } else if (_phase == 'post_checking') {
            _advanceToNextPart();
          }
        }
      });
    });
  }

  void _startPlaying() {
    setState(() {
      _phase = 'playing';
      _playerController?.play();
    });
  }

  void _playerListener() {
    if (_playerController?.value.playerState == PlayerState.ended && _phase == 'playing') {
      setState(() {
        _phase = 'post_checking';
        _secondsRemaining = 30; // 30 seconds to check answers
        _timer?.cancel();
        _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) return;
          setState(() {
            if (_secondsRemaining > 0) {
              _secondsRemaining--;
            } else {
              timer.cancel();
              _advanceToNextPart();
            }
          });
        });
      });
    }
  }

  void _advanceToNextPart() {
    final provider = context.read<YoutubeProvider>();
    final exam = provider.fullExam;
    if (exam == null) return;
    
    if (_currentPartIndex < exam.parts.length - 1) {
      _currentPartIndex++;
      _startPart(exam.parts[_currentPartIndex]);
    } else {
      // Finished all 4 parts
      setState(() {
        _phase = 'finished';
      });
      _showResults(exam);
    }
  }

  void _showResults(IeltsFullExamResponse exam) {
    // Basic scoring logic - can be expanded
    int score = 0;
    int totalQuestions = 0;
    
    List<Widget> resultWidgets = [];
    
    int globalQIndex = 0;
    for (var part in exam.parts) {
      for (var q in part.questions) {
        String userAnswer = _userAnswers[globalQIndex]?.toLowerCase().trim() ?? '';
        String correctAnswer = q.answer.toLowerCase().trim();
        
        // Very basic validation (case insensitive)
        bool isCorrect = userAnswer == correctAnswer;
        if (isCorrect) score++;
        totalQuestions++;
        
        resultWidgets.add(
          ListTile(
            title: Text('${globalQIndex + 1}. ${q.question}'),
            subtitle: Text('Твой ответ: ${_userAnswers[globalQIndex] ?? ''}\nПравильный: ${q.answer}'),
            trailing: Icon(isCorrect ? Icons.check_circle : Icons.cancel, color: isCorrect ? Colors.green : Colors.red),
          )
        );
        globalQIndex++;
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Результаты: $score / $totalQuestions'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(children: resultWidgets),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() {
                _examStarted = false;
                _phase = 'idle';
              });
            },
            child: const Text('Закрыть'),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<YoutubeProvider>();

    if (provider.isGeneratingExam) {
      return Scaffold(
        appBar: AppBar(title: const Text('IELTS Simulator')),
        body: LoadingOverlay(message: 'Генерируем часть ${provider.generatingPartNumber} из 4...\nПожалуйста, подождите.'),
      );
    }

    if (provider.examError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('IELTS Simulator')),
        body: EmptyState(
          icon: Icons.error_outline,
          message: 'Ошибка при генерации экзамена:\n${provider.examError}\n\nПопробуйте ещё раз.',
          actionLabel: 'Повторить',
          onAction: () => provider.generateFullExam(),
        ),
      );
    }

    if (!_examStarted && provider.fullExam == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('IELTS Simulator')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.headset, size: 64, color: Colors.blue),
              const SizedBox(height: 16),
              const Text(
                'IELTS Listening Simulator',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Симулятор включает 4 части (40 вопросов).\nДо начала каждой аудиозаписи дается 30 секунд на чтение вопросов.\nАудио проигрывается ровно один раз.',
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('Сгенерировать и начать тест'),
                onPressed: () => provider.generateFullExam(),
              ),
            ],
          ),
        ),
      );
    }

    if (!_examStarted && provider.fullExam != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('IELTS Simulator')),
        body: Center(
          child: FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text('Начать экзамен'),
            onPressed: () => _startExam(provider.fullExam!),
          ),
        ),
      );
    }

    final currentPart = provider.fullExam!.parts[_currentPartIndex];
    
    // Calculate global index offset for this part
    int globalIndexOffset = 0;
    for (int i = 0; i < _currentPartIndex; i++) {
      globalIndexOffset += provider.fullExam!.parts[i].questions.length;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('IELTS Exam'),
        actions: [
          TextButton(
            onPressed: () => _showResults(provider.fullExam!),
            child: const Text('Завершить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Part ${_currentPartIndex + 1} of 4',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                if (_phase == 'pre_reading')
                  Text('Чтение вопросов: $_secondsRemaining сек', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                if (_phase == 'playing')
                  const Text('Аудио воспроизводится...', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                if (_phase == 'post_checking')
                  Text('Проверка ответов: $_secondsRemaining сек', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          
          // Hidden Youtube Player to play the audio
          if (_playerController != null)
            SizedBox(
              height: 1, // practically hidden
              child: YoutubePlayer(
                controller: _playerController!,
                showVideoProgressIndicator: false,
              ),
            ),
            
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: currentPart.questions.length,
              itemBuilder: (context, index) {
                final q = currentPart.questions[index];
                final globalIndex = globalIndexOffset + index;
                
                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${globalIndex + 1}. ${q.question}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 12),
                        if (q.type == 'multiple_choice' && q.options.isNotEmpty)
                          ...q.options.map((opt) => RadioListTile<String>(
                            title: Text(opt),
                            value: opt,
                            groupValue: _userAnswers[globalIndex],
                            onChanged: (val) {
                              setState(() {
                                _userAnswers[globalIndex] = val!;
                              });
                            },
                          )),
                        if (q.type == 'completion' || q.type == 'matching' || q.options.isEmpty)
                          TextField(
                            decoration: const InputDecoration(
                              hintText: 'Ваш ответ...',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (val) {
                              _userAnswers[globalIndex] = val;
                            },
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
