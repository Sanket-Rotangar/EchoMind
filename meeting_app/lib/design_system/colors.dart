import 'package:flutter/material.dart';

class AppColors {
  // Backgrounds
  static const Color background = Color(0xFF0B0B0F);
  static const Color surface = Color(0xFF111117);
  static const Color glassSurface = Color(0x0DFFFFFF); // rgba(255,255,255,0.05)
  
  // Accents
  static const Color primaryAccent = Color(0xFFFF9A8B);
  static const Color secondaryAccent = Color(0xFF6DD5FA);
  static const Color accentPink = Color(0xFFFF6A88);
  
  // Text
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF9CA3AF);
  
  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFFFF9A8B), Color(0xFFFF6A88)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient secondaryGradient = LinearGradient(
    colors: [Color(0xFF6DD5FA), Color(0xFF2193B0)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient glowGradient = LinearGradient(
    colors: [
      Color(0x33FF9A8B),
      Color(0x00FF9A8B),
    ],
    begin: Alignment.center,
    end: Alignment.bottomCenter,
  );
  
  // Status colors
  static const Color statusCompleted = Color(0xFF10B981);
  static const Color statusProcessing = Color(0xFFF59E0B);
  static const Color statusFailed = Color(0xFFEF4444);
  
  // Borders
  static const Color borderGlass = Color(0x1AFFFFFF);
  static const Color borderAccent = Color(0x33FF9A8B);
}
