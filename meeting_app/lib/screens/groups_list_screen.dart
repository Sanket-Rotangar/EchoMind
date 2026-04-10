import 'package:flutter/material.dart';

import '../core/api_service.dart';
import '../core/theme.dart';
import 'group_detail_screen.dart';

class GroupsListScreen extends StatefulWidget {
  const GroupsListScreen({super.key});

  @override
  State<GroupsListScreen> createState() => _GroupsListScreenState();
}

class _GroupsListScreenState extends State<GroupsListScreen> {
  late Future<List<dynamic>> _groupsFuture;

  @override
  void initState() {
    super.initState();
    _groupsFuture = ApiService.getGroups();
  }

  void _refreshGroups() {
    setState(() {
      _groupsFuture = ApiService.getGroups();
    });
  }

  Future<void> _showCreateGroupDialog() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text(
          'Create Group',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Group Name',
                labelStyle: TextStyle(color: AppColors.textSecondary),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.divider),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.accent),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descController,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                labelStyle: TextStyle(color: AppColors.textSecondary),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.divider),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.accent),
                ),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Create', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      final name = nameController.text.trim();
      if (name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group name is required')),
        );
        return;
      }

      try {
        await ApiService.createGroup(
          name: name,
          description: descController.text.trim().isEmpty ? null : descController.text.trim(),
        );
        _refreshGroups();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Group created')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to create group: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        automaticallyImplyLeading: false, // Remove back button
        title: const Text(
          'Meeting Groups',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _groupsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'Failed to load groups',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _refreshGroups,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.black,
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final groups = snapshot.data!;

          return Column(
            children: [
              Expanded(
                child: groups.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.folder_open,
                              color: AppColors.textSecondary.withOpacity(0.5),
                              size: 64,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No groups yet',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Create a group to organize related meetings',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async => _refreshGroups(),
                        color: AppColors.accent,
                        backgroundColor: AppColors.cardBackground,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: groups.length,
                          itemBuilder: (context, index) {
                            final group = groups[index];
                            return _GroupCard(
                              group: group,
                              onTap: () async {
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => GroupDetailScreen(
                                      groupId: group['id'],
                                    ),
                                  ),
                                );
                                if (result == true) {
                                  _refreshGroups();
                                }
                              },
                            );
                          },
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _showCreateGroupDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Create Group'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final Map<String, dynamic> group;
  final VoidCallback onTap;

  const _GroupCard({
    required this.group,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = group['name'] as String? ?? 'Unnamed Group';
    final description = group['description'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.accent.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.folder,
            color: AppColors.accent,
            size: 24,
          ),
        ),
        title: Text(
          name,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: description != null && description.isNotEmpty
            ? Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  description,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              )
            : null,
        trailing: const Icon(
          Icons.arrow_forward_ios,
          color: AppColors.textSecondary,
          size: 16,
        ),
        onTap: onTap,
      ),
    );
  }
}
