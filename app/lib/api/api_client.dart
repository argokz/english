import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../core/constants.dart';
import '../models/deck.dart';
import '../models/card.dart' as app;
import '../models/similar_word.dart';

class EnrichWordSense {
  final String partOfSpeech;
  final String translation;
  final String example;
  EnrichWordSense({required this.partOfSpeech, required this.translation, required this.example});
}

class EnrichWordResult {
  final String? word; // английское слово для карточки (из API при вводе на русском)
  final String translation;
  final String example;
  final String? transcription;
  final String? pronunciationUrl;
  final List<EnrichWordSense> senses;
  EnrichWordResult({
    this.word,
    required this.translation,
    required this.example,
    this.transcription,
    this.pronunciationUrl,
    required this.senses,
  });
}

class TranslateResult {
  final String translation;
  final String sourceLang;
  final String targetLang;
  TranslateResult({required this.translation, required this.sourceLang, required this.targetLang});
}

class BackfillPosResult {
  final int updated;
  final int created;
  final int skipped;
  final int errors;
  BackfillPosResult({required this.updated, required this.created, required this.skipped, required this.errors});
}

/// Таймаут для запросов к Gemini (генерация слов, синонимы и т.д.).
const Duration _kLongRequestTimeout = Duration(seconds: 180);
/// Таймаут для backfill-pos: много карточек × запрос к AI — может занимать 5–10+ минут.
const Duration _kBackfillPosTimeout = Duration(minutes: 15);
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

  Future<app.CardModel> createCard(String deckId, {
    required String word,
    required String translation,
    String? example,
    String? transcription,
    String? pronunciationUrl,
    String? partOfSpeech,
  }) async {
    final data = <String, dynamic>{
      'word': word,
      'translation': translation,
      if (example != null && example.isNotEmpty) 'example': example,
      if (transcription != null && transcription.isNotEmpty) 'transcription': transcription,
      if (pronunciationUrl != null && pronunciationUrl.isNotEmpty) 'pronunciation_url': pronunciationUrl,
      if (partOfSpeech != null && partOfSpeech.isNotEmpty) 'part_of_speech': partOfSpeech,
    };
    final r = await _dio.post<Map<String, dynamic>>('decks/$deckId/cards', data: data);
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

  /// Запросить примеры предложений для карточки, сохранить в БД. Возвращает обновлённую карточку.
  Future<app.CardModel> fetchCardExamples(String deckId, String cardId) async {
    final r = await _dio.post<Map<String, dynamic>>(
      'decks/$deckId/cards/$cardId/fetch-examples',
      options: Options(receiveTimeout: _kLongRequestTimeout),
    );
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
  /// Возвращает количество добавленных и количество пропущенных дубликатов (уже в колоде).
  Future<GenerateWordsResult> generateWords({required String deckId, String? level, String? topic, int count = 20}) async {
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
    final d = r.data!;
    return GenerateWordsResult(
      created: d['created'] as int? ?? 0,
      skippedDuplicates: d['skipped_duplicates'] as int? ?? 0,
    );
  }

  Future<int> removeDuplicates(String deckId) async {
    final r = await _dio.post<Map<String, dynamic>>('decks/$deckId/remove-duplicates');
    return r.data!['removed'] as int? ?? 0;
  }

  /// Обновить карточки без части речи: добавить переводы по частям речи (сущ., глагол, прил., нареч.).
  Future<BackfillPosResult> backfillPos(String deckId, {int limit = 30}) async {
    final r = await _dio.post<Map<String, dynamic>>(
      'decks/$deckId/backfill-pos',
      data: {'limit': limit},
      options: Options(receiveTimeout: _kBackfillPosTimeout),
    );
    final d = r.data!;
    return BackfillPosResult(
      updated: d['updated'] as int? ?? 0,
      created: d['created'] as int? ?? 0,
      skipped: d['skipped'] as int? ?? 0,
      errors: d['errors'] as int? ?? 0,
    );
  }

  /// Translate text between Russian and English. sourceLang/targetLang: 'ru' | 'en'.
  Future<TranslateResult> translate(String text, {required String sourceLang, required String targetLang}) async {
    final r = await _dio.post<Map<String, dynamic>>(
      'ai/translate',
      data: {
        'text': text,
        'source_lang': sourceLang,
        'target_lang': targetLang,
      },
      options: Options(receiveTimeout: _kLongRequestTimeout),
    );
    final d = r.data!;
    return TranslateResult(
      translation: d['translation'] as String? ?? '',
      sourceLang: d['source_lang'] as String? ?? sourceLang,
      targetLang: d['target_lang'] as String? ?? targetLang,
    );
  }

  /// Enrich word: all senses by part of speech + common transcription and pronunciation.
  /// sourceLang: 'en' or 'ru' — язык введённого слова. Возвращает word (англ. слово для карточки).
  Future<EnrichWordResult> enrichWord(String word, {String sourceLang = 'en'}) async {
    final r = await _dio.post<Map<String, dynamic>>(
      'ai/enrich-word',
      data: {'word': word, 'source_lang': sourceLang},
      options: Options(receiveTimeout: _kLongRequestTimeout),
    );
    final d = r.data!;
    final sensesList = d['senses'] as List<dynamic>?;
    List<EnrichWordSense> senses = [];
    if (sensesList != null && sensesList.isNotEmpty) {
      for (final s in sensesList) {
        final m = s as Map<String, dynamic>?;
        if (m == null) continue;
        senses.add(EnrichWordSense(
          partOfSpeech: m['part_of_speech'] as String? ?? '',
          translation: m['translation'] as String? ?? '',
          example: m['example'] as String? ?? '',
        ));
      }
    }
    if (senses.isEmpty) {
      senses = [
        EnrichWordSense(
          partOfSpeech: '',
          translation: d['translation'] as String? ?? '',
          example: d['example'] as String? ?? '',
        ),
      ];
    }
    return EnrichWordResult(
      word: d['word'] as String?,
      translation: d['translation'] as String? ?? (senses.isNotEmpty ? senses.first.translation : ''),
      example: d['example'] as String? ?? (senses.isNotEmpty ? senses.first.example : ''),
      transcription: d['transcription'] as String?,
      pronunciationUrl: d['pronunciation_url'] as String?,
      senses: senses,
    );
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

  /// Список сохранённых проверок (история IELTS Письмо).
  Future<List<WritingSubmissionListItem>> getWritingHistory({int limit = 50, int offset = 0}) async {
    final r = await _dio.get<List>('ai/writing-history', queryParameters: {'limit': limit, 'offset': offset});
    return (r.data ?? []).map((e) => WritingSubmissionListItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Одна запись из истории (полные данные).
  Future<WritingSubmissionDetail> getWritingSubmission(String submissionId) async {
    final r = await _dio.get<Map<String, dynamic>>('ai/writing-history/$submissionId');
    return WritingSubmissionDetail.fromJson(r.data!);
  }

  /// IELTS Writing: проверка текста — оценка, исправления, ошибки, рекомендации. Сохраняется в историю.
  Future<EvaluateWritingResult> evaluateWriting({
    required String text,
    int? timeLimitMinutes,
    int? timeUsedSeconds,
    int? wordLimitMin,
    int? wordLimitMax,
    String? taskType,
  }) async {
    final r = await _dio.post<Map<String, dynamic>>(
      'ai/evaluate-writing',
      data: {
        'text': text,
        if (timeLimitMinutes != null) 'time_limit_minutes': timeLimitMinutes,
        if (timeUsedSeconds != null) 'time_used_seconds': timeUsedSeconds,
        if (wordLimitMin != null) 'word_limit_min': wordLimitMin,
        if (wordLimitMax != null) 'word_limit_max': wordLimitMax,
        if (taskType != null && taskType.isNotEmpty) 'task_type': taskType,
      },
      options: Options(receiveTimeout: _kLongRequestTimeout),
    );
    return EvaluateWritingResult.fromJson(r.data!);
  }
}

class GenerateWordsResult {
  final int created;
  final int skippedDuplicates;
  GenerateWordsResult({required this.created, required this.skippedDuplicates});
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

class WritingErrorItem {
  final String type;
  final String original;
  final String correction;
  final String explanation;
  WritingErrorItem({
    required this.type,
    required this.original,
    required this.correction,
    required this.explanation,
  });
  factory WritingErrorItem.fromJson(Map<String, dynamic> json) {
    return WritingErrorItem(
      type: json['type'] as String? ?? '',
      original: json['original'] as String? ?? '',
      correction: json['correction'] as String? ?? '',
      explanation: json['explanation'] as String? ?? '',
    );
  }
}

class EvaluateWritingResult {
  final String? submissionId;
  final int wordCount;
  final int? timeUsedSeconds;
  final double? bandScore; // IELTS 0–9, step 0.5
  final String evaluation;
  final String correctedText;
  final List<WritingErrorItem> errors;
  final String recommendations;
  EvaluateWritingResult({
    this.submissionId,
    required this.wordCount,
    this.timeUsedSeconds,
    this.bandScore,
    required this.evaluation,
    required this.correctedText,
    required this.errors,
    required this.recommendations,
  });
  factory EvaluateWritingResult.fromJson(Map<String, dynamic> json) {
    final errorsList = json['errors'] as List? ?? [];
    final band = json['band_score'];
    return EvaluateWritingResult(
      submissionId: json['submission_id'] as String?,
      wordCount: json['word_count'] as int? ?? 0,
      timeUsedSeconds: json['time_used_seconds'] as int?,
      bandScore: band != null ? (band is num ? band.toDouble() : double.tryParse(band.toString())) : null,
      evaluation: json['evaluation'] as String? ?? '',
      correctedText: json['corrected_text'] as String? ?? '',
      errors: errorsList.map((e) => WritingErrorItem.fromJson(e as Map<String, dynamic>)).toList(),
      recommendations: json['recommendations'] as String? ?? '',
    );
  }
}

class WritingSubmissionListItem {
  final String id;
  final int wordCount;
  final int? timeUsedSeconds;
  final DateTime createdAt;
  final String evaluationPreview;
  WritingSubmissionListItem({
    required this.id,
    required this.wordCount,
    this.timeUsedSeconds,
    required this.createdAt,
    required this.evaluationPreview,
  });
  factory WritingSubmissionListItem.fromJson(Map<String, dynamic> json) {
    return WritingSubmissionListItem(
      id: json['id'] as String,
      wordCount: json['word_count'] as int? ?? 0,
      timeUsedSeconds: json['time_used_seconds'] as int?,
      createdAt: DateTime.parse(json['created_at'] as String),
      evaluationPreview: json['evaluation_preview'] as String? ?? '',
    );
  }
}

class WritingSubmissionDetail {
  final String id;
  final String originalText;
  final int wordCount;
  final int? timeUsedSeconds;
  final int? timeLimitMinutes;
  final int? wordLimitMin;
  final int? wordLimitMax;
  final String? taskType;
  final String evaluation;
  final String correctedText;
  final List<WritingErrorItem> errors;
  final String recommendations;
  final DateTime createdAt;
  WritingSubmissionDetail({
    required this.id,
    required this.originalText,
    required this.wordCount,
    this.timeUsedSeconds,
    this.timeLimitMinutes,
    this.wordLimitMin,
    this.wordLimitMax,
    this.taskType,
    required this.evaluation,
    required this.correctedText,
    required this.errors,
    required this.recommendations,
    required this.createdAt,
  });
  factory WritingSubmissionDetail.fromJson(Map<String, dynamic> json) {
    final errorsList = json['errors'] as List? ?? [];
    return WritingSubmissionDetail(
      id: json['id'] as String,
      originalText: json['original_text'] as String? ?? '',
      wordCount: json['word_count'] as int? ?? 0,
      timeUsedSeconds: json['time_used_seconds'] as int?,
      timeLimitMinutes: json['time_limit_minutes'] as int?,
      wordLimitMin: json['word_limit_min'] as int?,
      wordLimitMax: json['word_limit_max'] as int?,
      taskType: json['task_type'] as String?,
      evaluation: json['evaluation'] as String? ?? '',
      correctedText: json['corrected_text'] as String? ?? '',
      errors: errorsList.map((e) => WritingErrorItem.fromJson(e as Map<String, dynamic>)).toList(),
      recommendations: json['recommendations'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
