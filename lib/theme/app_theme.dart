// theme/app_theme.dart
import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData lightTheme() {
    return ThemeData(
      primaryColor: Color(0xFF2E5BFF),
      primaryColorLight: Color(0xFF8C54FF),
      scaffoldBackgroundColor: Color(0xFFF9FAFC),
      fontFamily: 'Dubai',
      appBarTheme: AppBarTheme(
        color: Colors.white,
        elevation: 1,
        iconTheme: IconThemeData(color: Color(0xFF2E5BFF)),
        titleTextStyle: TextStyle(
          fontFamily: 'Tajawal',
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Color(0xFF2E5BFF),
          padding: EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Color(0xFF2E5BFF),
          padding: EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Color(0xFF2E5BFF)),
        ),
      ),
    );
  }
}
