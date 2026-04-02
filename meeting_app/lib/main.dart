import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'screens/main_layout.dart';

void main() {
  runApp(const SmartMeetingApp());
}

class SmartMeetingApp extends StatelessWidget {
  const SmartMeetingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Soora AI',
      theme: ThemeData(
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primaryPeach,
          surface: AppColors.surface,
          background: AppColors.background,
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(color: AppColors.textPrimary, fontSize: 32, fontWeight: FontWeight.bold),
          titleLarge: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w600),
          bodyLarge: TextStyle(color: AppColors.textPrimary, fontSize: 16),
          bodyMedium: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        useMaterial3: true,
      ),
      home: const MainLayout(),
    );
  }
}