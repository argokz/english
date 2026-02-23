import 'package:flutter/foundation.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../api/api_client.dart';
import 'auth_provider.dart';

class YoutubeProvider with ChangeNotifier {
  final AuthProvider auth;
  List<YouTubeHistoryItem> _history = [];
  bool _isLoadingHistory = false;
  
  // Search results
  List<YouTubeSearchResult> _searchResults = [];
  bool _isSearching = false;
  
  // Current playing/processing video
  YouTubeProcessResult? _currentVideo;
  bool _isProcessing = false;
  String? _processingError;

  // Questions for current video
  YouTubeQuestionsResult? _questions;
  bool _isLoadingQuestions = false;
  String? _questionsError;

  // Full IELTS Exam
  IeltsFullExamResponse? _fullExam;
  bool _isGeneratingExam = false;
  String? _examError;

  YoutubeProvider(this.auth);

  List<YouTubeHistoryItem> get history => _history;
  bool get isLoadingHistory => _isLoadingHistory;
  
  List<YouTubeSearchResult> get searchResults => _searchResults;
  bool get isSearching => _isSearching;
  
  YouTubeProcessResult? get currentVideo => _currentVideo;
  bool get isProcessing => _isProcessing;
  String? get processingError => _processingError;

  YouTubeQuestionsResult? get questions => _questions;
  bool get isLoadingQuestions => _isLoadingQuestions;
  String? get questionsError => _questionsError;

  IeltsFullExamResponse? get fullExam => _fullExam;
  bool get isGeneratingExam => _isGeneratingExam;
  String? get examError => _examError;

  Future<void> fetchHistory({int limit = 50, int offset = 0}) async {
    _isLoadingHistory = true;
    notifyListeners();
    try {
      final res = await auth.api.getYoutubeHistory(limit: limit, offset: offset);
      if (offset == 0) {
        _history = res;
      } else {
        _history.addAll(res);
      }
    } catch (e) {
      debugPrint('Error fetching youtube history: $e');
    } finally {
      _isLoadingHistory = false;
      notifyListeners();
    }
  }

  Future<void> searchYoutube(String query) async {
    _isSearching = true;
    _searchResults = [];
    notifyListeners();
    try {
      final res = await auth.api.searchYoutube(query);
      _searchResults = res;
    } catch (e) {
      debugPrint('Error searching youtube: $e');
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  Future<void> _startBackgroundExecution() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final config = const FlutterBackgroundAndroidConfig(
          notificationTitle: "Идет обработка видео",
          notificationText: "Пожалуйста, подождите, пока идет транскрибация",
          notificationImportance: AndroidNotificationImportance.normal,
          notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
        );
        bool initialized = await FlutterBackground.initialize(androidConfig: config);
        if (initialized) {
          await FlutterBackground.enableBackgroundExecution();
        }
      }
      WakelockPlus.enable();
    } catch (e) {
      debugPrint('Background execution error: $e');
    }
  }

  Future<void> _stopBackgroundExecution() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        if (FlutterBackground.isBackgroundExecutionEnabled) {
          await FlutterBackground.disableBackgroundExecution();
        }
      }
      WakelockPlus.disable();
    } catch (e) {
      debugPrint('Stop background error: $e');
    }
  }

  Future<bool> processVideo({String? url}) async {
    _isProcessing = true;
    _processingError = null;
    _currentVideo = null;
    _questions = null;
    notifyListeners();
    await _startBackgroundExecution();
    try {
      final res = await auth.api.processYoutubeVideo(url: url);
      _currentVideo = res;
      _isProcessing = false;
      notifyListeners();
      
      // Attempt to load questions in the background
      generateQuestions(res.id);
      
      return true;
    } catch (e) {
      debugPrint('Error processing youtube video: $e');
      _processingError = e.toString();
      _isProcessing = false;
      notifyListeners();
      return false;
    } finally {
      if (!_isLoadingQuestions) {
        await _stopBackgroundExecution();
      }
    }
  }

  Future<void> generateQuestions(String videoId) async {
    _isLoadingQuestions = true;
    _questionsError = null;
    notifyListeners();
    await _startBackgroundExecution();
    try {
      final res = await auth.api.generateYoutubeQuestions(videoId);
      _questions = res;
    } catch (e) {
      debugPrint('Error generating questions: $e');
      _questionsError = "Failed to load questions.";
    } finally {
      _isLoadingQuestions = false;
      notifyListeners();
      if (!_isProcessing) {
        await _stopBackgroundExecution();
      }
    }
  }

  Future<void> generateFullExam() async {
    _isGeneratingExam = true;
    _examError = null;
    notifyListeners();
    await _startBackgroundExecution();
    try {
      final res = await auth.api.generateFullIeltsExam();
      _fullExam = res;
    } catch (e) {
      debugPrint('Error generating full exam: $e');
      _examError = "Failed to generate exam: $e";
    } finally {
      _isGeneratingExam = false;
      notifyListeners();
      await _stopBackgroundExecution();
    }
  }

  Future<String> askQuestion(String videoId, String text) async {
    try {
      return await auth.api.askYoutubeQuestion(videoId, text);
    } catch (e) {
      debugPrint('Error asking question: $e');
      return "Error: Could not get an answer.";
    }
  }
  
  void selectVideoFromHistory(YouTubeHistoryItem item) {
    _currentVideo = YouTubeProcessResult(
      id: item.id,
      videoId: item.videoId,
      url: item.url,
      transcription: item.transcription,
      translation: "", // Translate again or cache translation if needed
      summary: "",
    );
    _questions = null;
    notifyListeners();
    generateQuestions(item.id);
  }
}
