import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color navy = Color(0xFF0B3D2E);
  static const Color green = Color(0xFF1B7A4E);
  static const Color mint = Color(0xFFE8F5EE);
  static const Color amber = Color(0xFFE8A838);
  static const Color danger = Color(0xFFC44536);
}

class AppTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.green,
        brightness: Brightness.light,
      ),
    );
    return base.copyWith(
      textTheme: GoogleFonts.manropeTextTheme(base.textTheme),
      scaffoldBackgroundColor: const Color(0xFFF4F7F5),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        centerTitle: false,
      ),
    );
  }
}
