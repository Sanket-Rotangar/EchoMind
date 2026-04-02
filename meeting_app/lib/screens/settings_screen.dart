import 'package:flutter/material.dart';

import '../core/theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      backgroundColor: AppColors.background,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionCard(
            title: 'Profile',
            child: Column(
              children: const [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Sanket Rotangar', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                  subtitle: Text('sanket@example.com', style: TextStyle(color: AppColors.textSecondary)),
                  leading: CircleAvatar(
                    backgroundColor: AppColors.border,
                    child: Icon(Icons.person, color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Preferences',
            child: Column(
              children: const [
                _SwitchTile(label: 'Background Listening', value: true),
                Divider(color: AppColors.border),
                _SwitchTile(label: 'Notifications', value: true),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Account',
            child: Column(
              children: const [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.download_rounded, color: AppColors.primaryPeach),
                  title: Text('Export Data', style: TextStyle(color: AppColors.textPrimary)),
                ),
                Divider(color: AppColors.border),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.logout_rounded, color: AppColors.primaryPeach),
                  title: Text('Log Out', style: TextStyle(color: AppColors.textPrimary)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
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
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
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
      activeThumbColor: AppColors.primaryPeach,
      onChanged: (next) {
        setState(() => _value = next);
      },
    );
  }
}
