import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'home_record_screen.dart';
import 'meetings_list_screen.dart';
import 'settings_screen.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 0;
  final GlobalKey<MeetingsListScreenState> _meetingsKey =
      GlobalKey<MeetingsListScreenState>();

  void _handleUploadComplete() {
    setState(() {
      _currentIndex = 1;
    });

    _meetingsKey.currentState?.reloadMeetings();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeRecordScreen(onUploadComplete: _handleUploadComplete),
      MeetingsListScreen(key: _meetingsKey),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border, width: 1)),
        ),
        child: BottomNavigationBar(
          backgroundColor: AppColors.background,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: AppColors.primaryPeach,
          unselectedItemColor: AppColors.textSecondary,
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.mic), label: 'Home'),
            BottomNavigationBarItem(
              icon: Icon(Icons.format_list_bulleted),
              label: 'Meetings',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
