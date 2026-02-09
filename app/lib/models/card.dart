class CardModel {
  final String id;
  final String deckId;
  final String word;
  final String translation;
  final String? example;
  final DateTime createdAt;
  final String state;
  final DateTime due;

  CardModel({
    required this.id,
    required this.deckId,
    required this.word,
    required this.translation,
    this.example,
    required this.createdAt,
    required this.state,
    required this.due,
  });

  factory CardModel.fromJson(Map<String, dynamic> json) {
    return CardModel(
      id: json['id'] as String,
      deckId: json['deck_id'] as String,
      word: json['word'] as String,
      translation: json['translation'] as String,
      example: json['example'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      state: json['state'] as String? ?? 'learning',
      due: DateTime.parse(json['due'] as String),
    );
  }
}
