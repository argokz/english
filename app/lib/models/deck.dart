class Deck {
  final String id;
  final String name;
  final DateTime createdAt;

  Deck({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  factory Deck.fromJson(Map<String, dynamic> json) {
    return Deck(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
