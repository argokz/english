import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../core/constants.dart';
import '../models/deck.dart';
import '../models/card.dart' as app;
import '../models/similar_word.dart';

/// Таймаут для запросов к Gemini (генерация слов, бэкфилл, синонимы): ждём ответа долго, прерываем только при реальной ошибке.
const Duration _kLongRequestTimeout = Duration(seconds: 180);
const Duration _kConnectTimeout = Duration(seconds: 20);
const Duration _kDefaultReceiveTimeout = Duration(seconds: 90);

class ApiClient {
  ApiClient({required this.getToken, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: kBaseUrl,
              connectTimeout: _kConnectTimeout,
              receiveTimeout: _kDefaultReceiveTimeout,
            )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await getToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        if (kDebugMode) {
          final uri = options.uri;
          debugPrint('[API] ${options.method} $uri');
        }
        return handler.next(options);
      },
      onError: (err, handler) {
        if (kDebugMode) {
          debugPrint('[API] ERROR ${err.requestOptions.uri} => ${err.type} ${err.message}');
          if (err.response != null) {
            debugPrint('[API] response ${err.response?.statusCode} ${err.response?.data}');
          }
        }
        return handler.next(err);
      },
    ));
  }

  final Future<String?> Function() getToken;
  final Dio _dio;

  String get baseUrl => kBaseUrl;

  /// GET /health без авторизации. Для проверки доступности сервера.
  Future<Map<String, dynamic>> getHealth() async {
    final r = await _dio.get<Map<String, dynamic>>('health');
    return r.data ?? {};
  }

  // Auth: open in browser
  String get googleLoginUrl => '$baseUrl/auth/google';

  /// Exchange Google ID token (from native sign-in) for our JWT. Returns map for AuthProvider.saveFromCallback.
  Future<Map<String, String>?> loginWithGoogleIdToken(String idToken) async {
    final r = await _dio.post<Map<String, dynamic>>(
      'auth/google/token',
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

  // Decks — пути без ведущего /, чтобы baseUrl .../english-words/ не терялся
  Future<List<Deck>> getDecks() async {
    final r = await _dio.get<List>('decks');
    return (r.data ?? []).map((e) => Deck.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Deck> createDeck(String name) async {
    final r = await _dio.post<Map<String, dynamic>>('decks', data: {'name': name});
    return Deck.fromJson(r.data!);
  }

  Future<Deck> getDeck(String deckId) async {
    final r = await _dio.get<Map<String, dynamic>>('decks/$deckId');
    return Deck.fromJson(r.data!);
  }

  Future<Deck> updateDeck(String deckId, String name) async {
    final r = await _dio.patch<Map<String, dynamic>>('decks/$deckId', data: {'name': name});
    return Deck.fromJson(r.data!);
  }

  Future<void> deleteDeck(String deckId) async {
    await _dio.delete('decks/$deckId');
  }

  // Cards
  Future<List<app.CardModel>> getCards(String deckId) async {
    final r = await _dio.get<List>('decks/$deckId/cards');
    return (r.data ?? []).map((e) => app.CardModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<app.CardModel>> getDueCards(String deckId) async {
    final r = await _dio.get<List>('decks/$deckId/due');
    return (r.data ?? []).map((e) => app.CardModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<app.CardModel> createCard(String deckId, {required String word, required String translation, String? example, String? transcription, String? pronunciationUrl}) async {
    final r = await _dio.post<Map<String, dynamic>>('decks/$deckId/cards', data: {
      'word': word,
      'translation': translation,
      if (example != null && example.isNotEmpty) 'example': example,
      if (transcription != null && transcription.isNotEmpty) 'transcription': transcription,
      if (pronunciationUrl != null && pronunciationUrl.isNotEmpty) 'pronunciation_url': pronunciationUrl,
    });
    return app.CardModel.fromJson(r.data!);
  }

  Future<app.CardModel> updateCard(String cardId, {String? word, String? translation, String? example}) async {
    final r = await _dio.patch<Map<String, dynamic>>('cards/$cardId', data: {
      if (word != null) 'word': word,
      if (translation != null) 'translation': translation,
      if (example != null) 'example': example,
    });
    return app.CardModel.fromJson(r.data!);
  }

  Future<void> deleteCard(String cardId) async {
    await _dio.delete('cards/$cardId');
  }

  Future<app.CardModel> reviewCard(String cardId, int rating) async {
    final r = await _dio.post<Map<String, dynamic>>('cards/$cardId/review', data: {'rating': rating});
    return app.CardModel.fromJson(r.data!);
  }

  // AI — длинные запросы к Gemini используют увеличенный таймаут
  Future<int> generateWords({required String deckId, String? level, String? topic, int count = 20}) async {
    final r = await _dio.post<Map<String, dynamic>>(
      'ai/generate-words',
      data: {
        'deck_id': deckId,
        if (level != null) 'level': level,
        if (topic != null) 'topic': topic,
        'count': count,
      },
      options: Options(receiveTimeout: _kLongRequestTimeout),
    );
    return r.data!['created'] as int;
  }

  Future<Map<String, String>> enrichWord(String word) async {
    final r = await _dio.post<Map<String, dynamic>>(
      'ai/enrich-word',
      data: {'word': word},
      options: Options(receiveTimeout: _kLongRequestTimeout),
    );
    return {
      'translation': r.data!['translation'] as String? ?? '',
      'example': r.data!['example'] as String? ?? '',
      'transcription': r.data!['transcription'] as String? ?? '',
      'pronunciation_url': r.data!['pronunciation_url'] as String? ?? '',
    };
  }

  Future<List<SimilarWord>> similarWords(String word, {String? deckId, int limit = 10}) async {
    final q = {'word': word, 'limit': limit};
    if (deckId != null) q['deck_id'] = deckId;
    final r = await _dio.get<List>('ai/similar-words', queryParameters: q);
    return (r.data ?? []).map((e) => SimilarWord.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Backfill transcription and pronunciation for cards that don't have them.
  Future<int> backfillTranscriptions({String? deckId, int limit = 50}) async {
    final r = await _dio.post<Map<String, dynamic>>(
      'ai/backfill-transcriptions',
      data: {
        if (deckId != null) 'deck_id': deckId,
        'limit': limit,
      },
      options: Options(receiveTimeout: _kLongRequestTimeout),
    );
    return r.data!['updated'] as int;
  }

  /// Synonyms via Gemini; returns synonyms list and cards already in deck.
  Future<SynonymsResult> getSynonyms(String word, {required String deckId, int limit = 10}) async {
    final r = await _dio.get<Map<String, dynamic>>(
      'ai/synonyms',
      queryParameters: {
        'word': word,
        'deck_id': deckId,
        'limit': limit,
      },
      options: Options(receiveTimeout: _kLongRequestTimeout),
    );
    final d = r.data!;
    final cardsInDeck = (d['cards_in_deck'] as List?)
        ?.map((e) => SimilarWord.fromJson(e as Map<String, dynamic>))
        .toList() ?? [];
    return SynonymsResult(
      synonyms: List<String>.from(d['synonyms'] as List? ?? []),
      cardsInDeck: cardsInDeck,
    );
  }

  /// Suggest synonym groups for deck (Gemini clusters).
  Future<List<SynonymGroup>> suggestSynonymGroups(String deckId, {int limit = 30}) async {
    final r = await _dio.post<Map<String, dynamic>>(
      'ai/synonym-groups/suggest',
      queryParameters: {'deck_id': deckId, 'limit': limit},
      options: Options(receiveTimeout: _kLongRequestTimeout),
    );
    final list = r.data!['groups'] as List? ?? [];
    return list.map((e) => SynonymGroup.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Apply synonym groups (set group id for given card groups).
  Future<void> applySynonymGroups(String deckId, List<List<String>> groups) async {
    await _dio.post('decks/$deckId/synonym-groups', data: {'groups': groups});
  }
}

class SynonymsResult {
  final List<String> synonyms;
  final List<SimilarWord> cardsInDeck;
  SynonymsResult({required this.synonyms, required this.cardsInDeck});
}

class SynonymGroup {
  final List<String> words;
  final List<String> cardIds;
  SynonymGroup({required this.words, required this.cardIds});
  factory SynonymGroup.fromJson(Map<String, dynamic> json) {
    return SynonymGroup(
      words: List<String>.from(json['words'] as List? ?? []),
      cardIds: List<String>.from(json['card_ids'] as List? ?? []),
    );
  }
}
