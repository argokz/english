class SimilarWord {
  final String word;
  final String translation;
  final String? example;
  final String cardId;

  SimilarWord({
    required this.word,
    required this.translation,
    this.example,
    required this.cardId,
  });

  factory SimilarWord.fromJson(Map<String, dynamic> json) {
    return SimilarWord(
      word: json['word'] as String,
      translation: json['translation'] as String,
      example: json['example'] as String?,
      cardId: json['card_id'] as String,
    );
  }
}
