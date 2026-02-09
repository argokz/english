import 'package:dio/dio.dart';
import '../core/constants.dart';
import '../models/deck.dart';
import '../models/card.dart' as app;
import '../models/similar_word.dart';

class ApiClient {
  ApiClient({required this.getToken, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: kBaseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
            )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await getToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
    ));
  }

  final Future<String?> Function() getToken;
  final Dio _dio;

  String get baseUrl => kBaseUrl;

  // Auth: open in browser
  String get googleLoginUrl => '$baseUrl/auth/google';

  /// Exchange Google ID token (from native sign-in) for our JWT. Returns map for AuthProvider.saveFromCallback.
  Future<Map<String, String>?> loginWithGoogleIdToken(String idToken) async {
    final r = await _dio.post<Map<String, dynamic>>(
      '/auth/google/token',
      data: {'id_token': idToken},
    );
    final d = r.data!;
    return {
      'access_token': d['access_token'] as String,
      'user_id': (d['user_id'] as dynamic)?.toString() ?? '',
      'email': (d['email'] as dynamic)?.toString() ?? '',
      'name': (d['name'] as dynamic)?.toString() ?? '',
    };
  }

  // Decks
  Future<List<Deck>> getDecks() async {
    final r = await _dio.get<List>('/decks');
    return (r.data ?? []).map((e) => Deck.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Deck> createDeck(String name) async {
    final r = await _dio.post<Map<String, dynamic>>('/decks', data: {'name': name});
    return Deck.fromJson(r.data!);
  }

  Future<Deck> getDeck(String deckId) async {
    final r = await _dio.get<Map<String, dynamic>>('/decks/$deckId');
    return Deck.fromJson(r.data!);
  }

  Future<Deck> updateDeck(String deckId, String name) async {
    final r = await _dio.patch<Map<String, dynamic>>('/decks/$deckId', data: {'name': name});
    return Deck.fromJson(r.data!);
  }

  Future<void> deleteDeck(String deckId) async {
    await _dio.delete('/decks/$deckId');
  }

  // Cards
  Future<List<app.CardModel>> getCards(String deckId) async {
    final r = await _dio.get<List>('/decks/$deckId/cards');
    return (r.data ?? []).map((e) => app.CardModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<app.CardModel>> getDueCards(String deckId) async {
    final r = await _dio.get<List>('/decks/$deckId/due');
    return (r.data ?? []).map((e) => app.CardModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<app.CardModel> createCard(String deckId, {required String word, required String translation, String? example}) async {
    final r = await _dio.post<Map<String, dynamic>>('/decks/$deckId/cards', data: {
      'word': word,
      'translation': translation,
      if (example != null && example.isNotEmpty) 'example': example,
    });
    return app.CardModel.fromJson(r.data!);
  }

  Future<app.CardModel> updateCard(String cardId, {String? word, String? translation, String? example}) async {
    final r = await _dio.patch<Map<String, dynamic>>('/cards/$cardId', data: {
      if (word != null) 'word': word,
      if (translation != null) 'translation': translation,
      if (example != null) 'example': example,
    });
    return app.CardModel.fromJson(r.data!);
  }

  Future<void> deleteCard(String cardId) async {
    await _dio.delete('/cards/$cardId');
  }

  Future<app.CardModel> reviewCard(String cardId, int rating) async {
    final r = await _dio.post<Map<String, dynamic>>('/cards/$cardId/review', data: {'rating': rating});
    return app.CardModel.fromJson(r.data!);
  }

  // AI
  Future<int> generateWords({required String deckId, String? level, String? topic, int count = 20}) async {
    final r = await _dio.post<Map<String, dynamic>>('/ai/generate-words', data: {
      'deck_id': deckId,
      if (level != null) 'level': level,
      if (topic != null) 'topic': topic,
      'count': count,
    });
    return r.data!['created'] as int;
  }

  Future<Map<String, String>> enrichWord(String word) async {
    final r = await _dio.post<Map<String, dynamic>>('/ai/enrich-word', data: {'word': word});
    return {
      'translation': r.data!['translation'] as String? ?? '',
      'example': r.data!['example'] as String? ?? '',
    };
  }

  Future<List<SimilarWord>> similarWords(String word, {String? deckId, int limit = 10}) async {
    final q = {'word': word, 'limit': limit};
    if (deckId != null) q['deck_id'] = deckId;
    final r = await _dio.get<List>('/ai/similar-words', queryParameters: q);
    return (r.data ?? []).map((e) => SimilarWord.fromJson(e as Map<String, dynamic>)).toList();
  }
}
