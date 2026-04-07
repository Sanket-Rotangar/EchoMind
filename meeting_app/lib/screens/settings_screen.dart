import 'package:flutter/material.dart';

import '../core/api_service.dart';
import '../core/auth_service.dart';
import '../core/theme.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AuthService _authService = AuthService();
  bool _isConnectingCalendar = false;
  bool _isDisconnectingCalendar = false;

  @override
  void initState() {
    super.initState();
    _authService.addListener(_onAuthChange);
    
    // Set up callback for OAuth completion via deep link
    _authService.onCalendarOAuthComplete = _onCalendarOAuthComplete;
  }

  @override
  void dispose() {
    _authService.removeListener(_onAuthChange);
    _authService.onCalendarOAuthComplete = null;
    super.dispose();
  }

  void _onAuthChange() {
    if (mounted) setState(() {});
  }
  
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

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;
    
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 8),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.name ?? 'User',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user?.email ?? '',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Google Calendar Section
            _buildSectionCard(
              title: 'Integrations',
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
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
                    title: const Text(
                      'Google Calendar',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      user?.calendarConnected == true
                          ? 'Connected - meetings will be added automatically'
                          : 'Connect to auto-add meeting events',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    trailing: _isConnectingCalendar || _isDisconnectingCalendar
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primaryPeach,
                            ),
                          )
                        : user?.calendarConnected == true
                            ? TextButton(
                                onPressed: _disconnectCalendar,
                                child: const Text(
                                  'Disconnect',
                                  style: TextStyle(color: Colors.red),
                                ),
                              )
                            : ElevatedButton(
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
                    leading: const Icon(Icons.download_rounded, color: AppColors.primaryPeach),
                    title: const Text(
                      'Export My Data',
                      style: TextStyle(color: AppColors.textPrimary),
                    ),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Coming soon!')),
                      );
                    },
                  ),
                  const Divider(color: AppColors.border),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.logout_rounded, color: Colors.red),
                    title: const Text(
                      'Sign Out',
                      style: TextStyle(color: Colors.red),
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
