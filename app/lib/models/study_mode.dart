enum StudyMode {
  englishToRussian,  // Показывать английское слово, вводить русский перевод
  russianToEnglish,  // Показывать русский перевод, вводить английское слово
  mixed,             // Смешанный режим (случайно выбирается направление)
}

extension StudyModeExtension on StudyMode {
  String get displayName {
    switch (this) {
      case StudyMode.englishToRussian:
        return 'Английский → Русский';
      case StudyMode.russianToEnglish:
        return 'Русский → Английский';
      case StudyMode.mixed:
        return 'Смешанный';
    }
  }

  String get storageKey {
    switch (this) {
      case StudyMode.englishToRussian:
        return 'english_to_russian';
      case StudyMode.russianToEnglish:
        return 'russian_to_english';
      case StudyMode.mixed:
        return 'mixed';
    }
  }

  static StudyMode fromStorageKey(String key) {
    switch (key) {
      case 'english_to_russian':
        return StudyMode.englishToRussian;
      case 'russian_to_english':
        return StudyMode.russianToEnglish;
      case 'mixed':
        return StudyMode.mixed;
      default:
        return StudyMode.englishToRussian;
    }
  }
}

