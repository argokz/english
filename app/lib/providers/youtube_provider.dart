import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import 'auth_provider.dart';

class YoutubeProvider with ChangeNotifier {
  final AuthProvider auth;
  List<YouTubeHistoryItem> _history = [];
  bool _isLoadingHistory = false;
  
  // Current playing/processing video
  YouTubeProcessResult? _currentVideo;
  bool _isProcessing = false;
  String? _processingError;

  // Questions for current video
  YouTubeQuestionsResult? _questions;
  bool _isLoadingQuestions = false;
  String? _questionsError;

  YoutubeProvider(this.auth);

  List<YouTubeHistoryItem> get history => _history;
  bool get isLoadingHistory => _isLoadingHistory;
  
  YouTubeProcessResult? get currentVideo => _currentVideo;
  bool get isProcessing => _isProcessing;
  String? get processingError => _processingError;

  YouTubeQuestionsResult? get questions => _questions;
  bool get isLoadingQuestions => _isLoadingQuestions;
  String? get questionsError => _questionsError;

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

  Future<bool> processVideo({String? url}) async {
    _isProcessing = true;
    _processingError = null;
    _currentVideo = null;
    _questions = null;
    notifyListeners();
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
    }
  }

  Future<void> generateQuestions(String videoId) async {
    _isLoadingQuestions = true;
    _questionsError = null;
    notifyListeners();
    try {
      final res = await auth.api.generateYoutubeQuestions(videoId);
      _questions = res;
    } catch (e) {
      debugPrint('Error generating questions: $e');
      _questionsError = "Failed to load questions.";
    } finally {
      _isLoadingQuestions = false;
      notifyListeners();
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
