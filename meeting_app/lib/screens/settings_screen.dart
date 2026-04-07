import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../core/api_service.dart';
import '../core/auth_service.dart';
// COMMENTED OUT - Call recording feature disabled due to Android limitations
// import '../core/call_recording_service.dart';
import '../core/theme.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  final AuthService _authService = AuthService();
  // COMMENTED OUT - Call recording feature disabled due to Android limitations
  // final CallRecordingService _callRecordingService = CallRecordingService();
  bool _isConnectingCalendar = false;
  bool _isDisconnectingCalendar = false;
  // COMMENTED OUT - Call recording feature disabled
  // bool _pendingCallRecordingEnable = false; // Track if we're waiting for permission

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authService.addListener(_onAuthChange);
    // COMMENTED OUT - Call recording feature disabled
    // _callRecordingService.addListener(_onCallRecordingChange);
    
    // Set up callback for OAuth completion via deep link
    _authService.onCalendarOAuthComplete = _onCalendarOAuthComplete;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authService.removeListener(_onAuthChange);
    // COMMENTED OUT - Call recording feature disabled
    // _callRecordingService.removeListener(_onCallRecordingChange);
    _authService.onCalendarOAuthComplete = null;
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // COMMENTED OUT - Call recording feature disabled
    // When app resumes (user returns from settings), re-check permissions
    // if (state == AppLifecycleState.resumed && _pendingCallRecordingEnable) {
    //   _checkCallRecordingPermissions();
    // }
  }
  
  // COMMENTED OUT - Call recording feature disabled
  // Future<void> _checkCallRecordingPermissions() async {
  //   final allGranted = await _callRecordingService.checkPermissions();
  //   debugPrint('Checking call recording permissions after resume: $allGranted');
  //   
  //   if (allGranted) {
  //     _pendingCallRecordingEnable = false;
  //     await _callRecordingService.refreshPermissionsAndEnable();
  //     
  //     if (mounted && _callRecordingService.isEnabled) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         const SnackBar(
  //           content: Text('Call recording enabled!'),
  //           backgroundColor: Colors.green,
  //         ),
  //       );
  //     }
  //   }
  // }

  void _onAuthChange() {
    if (mounted) setState(() {});
  }

  // COMMENTED OUT - Call recording feature disabled
  // void _onCallRecordingChange() {
  //   if (mounted) setState(() {});
  // }
  
  void _onCalendarOAuthComplete(bool success, String? error) {
    if (!mounted) return;
    
    setState(() => _isConnectingCalendar = false);
    
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Google Calendar connected successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error ?? 'Failed to connect calendar'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _connectGoogleCalendar() async {
    setState(() => _isConnectingCalendar = true);

    // Show a snackbar to indicate the process is starting
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Opening Google authorization...'),
          duration: Duration(seconds: 2),
        ),
      );
    }
    
    // Start the OAuth flow - this will:
    // 1. Start a local server to catch the callback
    // 2. Open the browser for Google authorization
    // 3. Handle the callback and connect the calendar
    // 4. Call _onCalendarOAuthComplete when done
    _authService.connectGoogleCalendar();
    
    // Note: _isConnectingCalendar will be set to false by _onCalendarOAuthComplete
  }

  Future<void> _disconnectCalendar() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Disconnect Calendar',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          'Are you sure you want to disconnect your Google Calendar? Meeting events will no longer be added automatically.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isDisconnectingCalendar = true);

    try {
      await ApiService.disconnectCalendar();
      await _authService.refreshCalendarStatus();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Calendar disconnected successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to disconnect: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDisconnectingCalendar = false);
      }
    }
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Sign Out',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          'Are you sure you want to sign out?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await _authService.signOut();
    
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _showExportDataDialog() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _ExportDataDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;
    
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // App Logo Header
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'EchoMind',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Settings',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            
            // Profile Section
            _buildSectionCard(
              title: 'Profile',
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppColors.primaryPeach.withOpacity(0.2),
                    backgroundImage: user?.photoUrl != null
                        ? NetworkImage(user!.photoUrl!)
                        : null,
                    child: user?.photoUrl == null
                        ? Text(
                            (user?.name ?? user?.email ?? '?')[0].toUpperCase(),
                            style: const TextStyle(
                              color: AppColors.primaryPeach,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      user?.name ?? 'User',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Connectors Section
            _buildSectionCard(
              title: 'Connectors',
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: user?.calendarConnected == true
                          ? Colors.green.withOpacity(0.15)
                          : AppColors.border,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.calendar_month,
                      color: user?.calendarConnected == true
                          ? Colors.green
                          : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Google Calendar',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (user?.calendarConnected == true)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  'Connected',
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_isConnectingCalendar || _isDisconnectingCalendar)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primaryPeach,
                      ),
                    )
                  else if (user?.calendarConnected == true)
                    TextButton(
                      onPressed: _disconnectCalendar,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      child: const Text(
                        'Disconnect',
                        style: TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    )
                  else
                    ElevatedButton(
                      onPressed: _connectGoogleCalendar,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryPeach,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      child: const Text('Connect'),
                    ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // COMMENTED OUT - Call recording feature disabled due to Android limitations
            // Call Recording Section
            /*
            _buildSectionCard(
              title: 'Call Recording',
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _callRecordingService.isEnabled
                              ? AppColors.primaryPeach.withOpacity(0.15)
                              : AppColors.border,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.phone_in_talk,
                          color: _callRecordingService.isEnabled
                              ? AppColors.primaryPeach
                              : AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Record Phone Calls',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _callRecordingService.isEnabled
                                  ? 'Popup will appear during calls'
                                  : 'Show recording popup on calls',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _callRecordingService.isEnabled,
                        activeColor: AppColors.primaryPeach,
                        onChanged: (value) async {
                          if (value) {
                            // Trying to enable - set flag so we check permissions on resume
                            _pendingCallRecordingEnable = true;
                          }
                          
                          await _callRecordingService.setEnabled(value);
                          
                          if (!_callRecordingService.isEnabled && value) {
                            // Permission was denied or user sent to settings
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Please grant overlay permission and return to the app'),
                                  backgroundColor: Colors.orange,
                                  duration: Duration(seconds: 3),
                                ),
                              );
                            }
                          } else if (_callRecordingService.isEnabled && value) {
                            // Successfully enabled
                            _pendingCallRecordingEnable = false;
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Call recording enabled!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } else if (!value) {
                            // User disabled it
                            _pendingCallRecordingEnable = false;
                          }
                        },
                      ),
                    ],
                  ),
                  if (_callRecordingService.isEnabled) ...[
                    const SizedBox(height: 16),
                    const Divider(color: AppColors.border),
                    const SizedBox(height: 12),
                    
                    // Recording Mode Selection
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Recording Mode',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // Microphone Only Option
                    _buildRecordingModeOption(
                      title: 'Microphone Only',
                      subtitle: 'Records your voice only',
                      icon: Icons.mic,
                      isSelected: _callRecordingService.recordingMode == RecordingMode.microphoneOnly,
                      onTap: () => _callRecordingService.setRecordingMode(RecordingMode.microphoneOnly),
                    ),
                    
                    const SizedBox(height: 8),
                    
                    // Both Sides Option (requires accessibility)
                    _buildRecordingModeOption(
                      title: 'Both Sides',
                      subtitle: _callRecordingService.isAndroid10OrHigher
                          ? 'Records both parties (Android 10+)'
                          : 'Requires Android 10 or higher',
                      icon: Icons.people,
                      isSelected: _callRecordingService.recordingMode == RecordingMode.systemAudio,
                      isEnabled: _callRecordingService.isAndroid10OrHigher,
                      onTap: () {
                        if (_callRecordingService.isAndroid10OrHigher) {
                          _callRecordingService.setRecordingMode(RecordingMode.systemAudio);
                        }
                      },
                    ),
                    
                    // Accessibility Service Setup (for Both Sides mode)
                    if (_callRecordingService.recordingMode == RecordingMode.systemAudio &&
                        _callRecordingService.isAndroid10OrHigher) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _callRecordingService.isAccessibilityEnabled
                              ? Colors.green.withOpacity(0.1)
                              : Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _callRecordingService.isAccessibilityEnabled
                                ? Colors.green.withOpacity(0.3)
                                : Colors.orange.withOpacity(0.3),
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _callRecordingService.isAccessibilityEnabled
                                      ? Icons.check_circle
                                      : Icons.warning_amber_rounded,
                                  color: _callRecordingService.isAccessibilityEnabled
                                      ? Colors.green
                                      : Colors.orange,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _callRecordingService.isAccessibilityEnabled
                                        ? 'Accessibility Service Enabled'
                                        : 'Accessibility Service Required',
                                    style: TextStyle(
                                      color: _callRecordingService.isAccessibilityEnabled
                                          ? Colors.green
                                          : Colors.orange,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (!_callRecordingService.isAccessibilityEnabled) ...[
                              const SizedBox(height: 10),
                              const Text(
                                'To record both sides of the call, enable the EchoMind Accessibility Service in your device settings.',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    await _callRecordingService.openAccessibilitySettings();
                                    // Wait a bit and then refresh the status
                                    await Future.delayed(const Duration(seconds: 1));
                                    await _callRecordingService.refreshAccessibilityStatus();
                                  },
                                  icon: const Icon(Icons.settings, size: 18),
                                  label: const Text('Open Accessibility Settings'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primaryPeach.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.primaryPeach.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: AppColors.primaryPeach.withOpacity(0.8),
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'A floating button will appear when you make or receive calls. Tap it to start recording.',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            */
            
            // Replacing Call Recording section with a notice
            _buildSectionCard(
              title: 'Call Recording',
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.phone_in_talk,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Not Available',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Call recording is blocked by Android security policies on this device',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Preferences
            _buildSectionCard(
              title: 'Preferences',
              child: Column(
                children: const [
                  _SwitchTile(label: 'Background Listening', value: true),
                  Divider(color: AppColors.border),
                  _SwitchTile(label: 'Push Notifications', value: true),
                  Divider(color: AppColors.border),
                  _SwitchTile(label: 'Auto-add to Calendar', value: true),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Account Actions
            _buildSectionCard(
              title: 'Account',
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.primaryPeach.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.download_rounded, color: AppColors.primaryPeach, size: 20),
                    ),
                    title: const Text(
                      'Export My Data',
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: AppColors.textSecondary.withOpacity(0.5),
                      size: 20,
                    ),
                    onTap: _showExportDataDialog,
                  ),
                  const Divider(color: AppColors.border),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.logout_rounded, color: Colors.red, size: 20),
                    ),
                    title: const Text(
                      'Sign Out',
                      style: TextStyle(color: Colors.red, fontSize: 15),
                    ),
                    onTap: _signOut,
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
            
            // App Version
            Center(
              child: Text(
                'EchoMind v1.0.0',
                style: TextStyle(
                  color: AppColors.textSecondary.withOpacity(0.5),
                  fontSize: 12,
                ),
              ),
            ),
            
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.primaryPeach,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  // COMMENTED OUT - Call recording feature disabled due to Android limitations
  /*
  Widget _buildRecordingModeOption({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    bool isEnabled = true,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryPeach.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryPeach
                : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primaryPeach.withOpacity(0.2)
                    : AppColors.border,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: isEnabled
                    ? (isSelected ? AppColors.primaryPeach : AppColors.textSecondary)
                    : AppColors.textSecondary.withOpacity(0.5),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isEnabled
                          ? AppColors.textPrimary
                          : AppColors.textSecondary.withOpacity(0.5),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isEnabled
                          ? AppColors.textSecondary
                          : AppColors.textSecondary.withOpacity(0.5),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: AppColors.primaryPeach,
                size: 22,
              ),
          ],
        ),
      ),
    );
  }
  */
}

class _SwitchTile extends StatefulWidget {
  final String label;
  final bool value;

  const _SwitchTile({required this.label, required this.value});

  @override
  State<_SwitchTile> createState() => _SwitchTileState();
}

class _SwitchTileState extends State<_SwitchTile> {
  late bool _value;

  @override
  void initState() {
    super.initState();
    _value = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(widget.label, style: const TextStyle(color: AppColors.textPrimary)),
      value: _value,
      activeColor: AppColors.primaryPeach,
      onChanged: (next) {
        setState(() => _value = next);
      },
    );
  }
}

class _ExportDataDialog extends StatefulWidget {
  const _ExportDataDialog();

  @override
  State<_ExportDataDialog> createState() => _ExportDataDialogState();
}

class _ExportDataDialogState extends State<_ExportDataDialog> {
  List<dynamic> _meetings = [];
  bool _isLoading = true;
  String? _error;
  String? _exportingId;

  @override
  void initState() {
    super.initState();
    _loadMeetings();
  }

  Future<void> _loadMeetings() async {
    try {
      final meetings = await ApiService.getMeetings(offset: 0, limit: 100);
      if (mounted) {
        setState(() {
          _meetings = meetings;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  String _formatDate(String? createdAt) {
    if (createdAt == null || createdAt.isEmpty) return 'Unknown date';
    final parsed = DateTime.tryParse(createdAt);
    if (parsed == null) return createdAt;

    const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final local = parsed.toLocal();
    final month = monthNames[local.month - 1];
    final day = local.day.toString().padLeft(2, '0');

    return '$month $day, ${local.year}';
  }

  Future<void> _exportMeeting(String meetingId, String title) async {
    setState(() => _exportingId = meetingId);

    try {
      final details = await ApiService.getMeetingDetails(meetingId);
      
      final exportData = {
        'meeting_id': meetingId,
        'title': details['title'],
        'created_at': details['created_at'],
        'status': details['status'],
        'transcript': details['transcript'],
        'intelligence_data': details['intelligence_data'],
        'exported_at': DateTime.now().toIso8601String(),
      };

      final jsonStr = const JsonEncoder.withIndent('  ').convert(exportData);
      
      final directory = await getApplicationDocumentsDirectory();
      final sanitizedTitle = title.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(' ', '_');
      final fileName = 'echomind_${sanitizedTitle}_$meetingId.json';
      final file = File('${directory.path}/$fileName');
      await file.writeAsString(jsonStr);

      if (mounted) {
        setState(() => _exportingId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported to ${file.path}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _exportingId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
          maxWidth: 400,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Icon(Icons.download_rounded, color: AppColors.primaryPeach),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Export Meeting Data',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.textSecondary),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.border, height: 1),
            Flexible(
              child: _isLoading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: CircularProgressIndicator(color: AppColors.primaryPeach),
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline, color: Colors.red, size: 40),
                                const SizedBox(height: 12),
                                Text(
                                  'Failed to load meetings',
                                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _error!,
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      : _meetings.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(40),
                                child: Text(
                                  'No meetings to export',
                                  style: TextStyle(color: AppColors.textSecondary),
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shrinkWrap: true,
                              itemCount: _meetings.length,
                              separatorBuilder: (_, __) => const Divider(
                                color: AppColors.border,
                                height: 1,
                                indent: 16,
                                endIndent: 16,
                              ),
                              itemBuilder: (context, index) {
                                final meeting = _meetings[index] as Map<String, dynamic>;
                                final title = (meeting['title'] ?? 'Untitled Meeting').toString();
                                final id = meeting['id']?.toString() ?? '';
                                final createdAt = meeting['created_at']?.toString();
                                final status = (meeting['status'] ?? '').toString().toLowerCase();
                                final isCompleted = status == 'completed';
                                final isExporting = _exportingId == id;

                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                                  title: Text(
                                    title,
                                    style: TextStyle(
                                      color: isCompleted ? AppColors.textPrimary : AppColors.textSecondary,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    _formatDate(createdAt),
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                  trailing: isExporting
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: AppColors.primaryPeach,
                                          ),
                                        )
                                      : isCompleted
                                          ? IconButton(
                                              icon: const Icon(
                                                Icons.file_download_outlined,
                                                color: AppColors.primaryPeach,
                                              ),
                                              onPressed: () => _exportMeeting(id, title),
                                              tooltip: 'Export',
                                            )
                                          : Tooltip(
                                              message: 'Processing - not ready for export',
                                              child: Icon(
                                                Icons.hourglass_empty,
                                                color: AppColors.textSecondary.withOpacity(0.5),
                                                size: 20,
                                              ),
                                            ),
                                );
                              },
                            ),
            ),
            const Divider(color: AppColors.border, height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppColors.textSecondary, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Exports include transcript, summary, and insights',
                      style: TextStyle(
                        color: AppColors.textSecondary.withOpacity(0.7),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
