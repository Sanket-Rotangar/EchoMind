import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../core/call_recording_service.dart';
import '../core/theme.dart';
import 'chat_screen.dart';
import 'groups_list_screen.dart';
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
  final CallRecordingService _callRecordingService = CallRecordingService();
  StreamSubscription? _overlayDataSubscription;

  @override
  void initState() {
    super.initState();
    // Temporarily disabled to avoid stream error
    // _setupOverlayListener();
  }

  @override
  void dispose() {
    _overlayDataSubscription?.cancel();
    super.dispose();
  }

  void _setupOverlayListener() {
    // Listen for messages from the overlay window
    // Use asBroadcastStream to allow multiple listeners during hot reload
    _overlayDataSubscription?.cancel(); // Cancel any existing subscription first
    try {
      _overlayDataSubscription = FlutterOverlayWindow.overlayListener.asBroadcastStream().listen((data) {
        if (data is Map) {
          final action = data['action'];
          if (action == 'start_recording') {
            _callRecordingService.startRecording();
          } else if (action == 'stop_recording') {
            _callRecordingService.stopRecording();
          }
        }
      });
    } catch (e) {
      // Ignore stream errors during development
      print('Overlay listener error (can be ignored): $e');
    }
  }

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
      const GroupsListScreen(),
      const ChatScreen(),
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
            BottomNavigationBarItem(icon: Icon(Icons.mic), label: 'Record'),
            BottomNavigationBarItem(
              icon: Icon(Icons.format_list_bulleted),
              label: 'Meetings',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.folder_outlined),
              label: 'Groups',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.auto_awesome),
              label: 'Assistant',
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
