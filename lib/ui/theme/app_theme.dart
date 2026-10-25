import 'dart:ui';
import 'package:flutter/material.dart';

/// Modern Dark & Glassmorphic theme definitions.
class AppTheme {
  static const Color background = Color(0xFF0D0D12);
  static const Color surface = Color(0xFF161622);
  static const Color surfaceLight = Color(0xFF222232);
  static const Color primary = Color(0xFF8A5CF6); // Modern Purple / Accent
  static const Color secondary = Color(0xFF38BDF8); // Cyan Accent
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color cardGlass = Color(0x331E1E2E);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        surface: surface,
      ),
      fontFamily: 'Inter',
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: textSecondary,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }

  /// Glassmorphic container decoration with subtle border and blur.
  static BoxDecoration glassDecoration({
    double borderRadius = 16,
    Color color = const Color(0x2AFFFFFF),
    Color borderColor = const Color(0x1AFFFFFF),
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: borderColor, width: 1.0),
      boxShadow: const [
        BoxShadow(
          color: Color(0x22000000),
          blurRadius: 16,
          offset: Offset(0, 8),
        ),
      ],
    );
  }
}
