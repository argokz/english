import 'package:flutter/material.dart';

/// Части речи: цвета и подписи для UI.
class PosColors {
  PosColors._();

  static const Color noun = Color(0xFF1976D2);      // синий
  static const Color verb = Color(0xFFD32F2F);      // красный
  static const Color adjective = Color(0xFF388E3C);  // зелёный
  static const Color adverb = Color(0xFFF57C00);     // оранжевый

  static Color colorFor(String? partOfSpeech) {
    if (partOfSpeech == null || partOfSpeech.isEmpty) return Colors.grey;
    switch (partOfSpeech.toLowerCase()) {
      case 'noun': return noun;
      case 'verb': return verb;
      case 'adjective': return adjective;
      case 'adverb': return adverb;
      default: return Colors.grey;
    }
  }

  static String labelFor(String? partOfSpeech) {
    if (partOfSpeech == null || partOfSpeech.isEmpty) return '';
    switch (partOfSpeech.toLowerCase()) {
      case 'noun': return 'сущ.';
      case 'verb': return 'глагол';
      case 'adjective': return 'прил.';
      case 'adverb': return 'нареч.';
      default: return partOfSpeech;
    }
  }
}
