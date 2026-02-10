import 'package:flutter/material.dart';

/// Общие константы и тема для единообразного UI.
class AppTheme {
  AppTheme._();

  static const double radiusMedium = 12;
  static const double radiusLarge = 16;
  static const double buttonMinHeight = 48;
  static const EdgeInsets paddingScreen = EdgeInsets.all(16);
  static const EdgeInsets paddingCard = EdgeInsets.all(16);

  static InputDecorationTheme get inputDecorationTheme => InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(radiusMedium)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radiusMedium)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radiusMedium)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );

  static FilledButtonThemeData get filledButtonTheme => FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, buttonMinHeight),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMedium)),
        ),
      );

  static CardTheme get cardTheme => CardTheme(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMedium)),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      );

  static SnackBarThemeData get snackBarTheme => SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMedium)),
        margin: const EdgeInsets.all(16),
      );

  static DialogTheme get dialogTheme => DialogTheme(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusLarge)),
        titleTextStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      );

  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        inputDecorationTheme: inputDecorationTheme,
        filledButtonTheme: filledButtonTheme,
        cardTheme: cardTheme,
        snackBarTheme: snackBarTheme,
        dialogTheme: dialogTheme,
      );
}
