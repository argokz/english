class CardModel {
  final String id;
  final String deckId;
  final String word;
  final String translation;
  final String? example;
  final String? transcription;
  final String? pronunciationUrl;
  final DateTime createdAt;
  final String state;
  final DateTime due;
  final String? synonymGroupId;
  final String? partOfSpeech;

  CardModel({
    required this.id,
    required this.deckId,
    required this.word,
    required this.translation,
    this.example,
    this.transcription,
    this.pronunciationUrl,
    required this.createdAt,
    required this.state,
    required this.due,
    this.synonymGroupId,
    this.partOfSpeech,
  });

  factory CardModel.fromJson(Map<String, dynamic> json) {
    return CardModel(
      id: json['id'] as String,
      deckId: json['deck_id'] as String,
      word: json['word'] as String,
      translation: json['translation'] as String,
      example: json['example'] as String?,
      transcription: json['transcription'] as String?,
      pronunciationUrl: json['pronunciation_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      state: json['state'] as String? ?? 'learning',
      due: DateTime.parse(json['due'] as String),
      synonymGroupId: json['synonym_group_id'] as String?,
      partOfSpeech: json['part_of_speech'] as String?,
    );
  }
}
