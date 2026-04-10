import 'package:flutter/material.dart';

import '../core/api_service.dart';
import '../core/theme.dart';
import 'group_chat_screen.dart';
import 'summary_screen.dart';

class GroupDetailScreen extends StatefulWidget {
  final String groupId;

  const GroupDetailScreen({super.key, required this.groupId});

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  late Future<Map<String, dynamic>> _groupFuture;

  @override
  void initState() {
    super.initState();
    _groupFuture = ApiService.getGroupDetail(widget.groupId);
  }

  void _refreshGroup() {
    setState(() {
      _groupFuture = ApiService.getGroupDetail(widget.groupId);
    });
  }

  Future<void> _showEditDialog(Map<String, dynamic> group) async {
    final nameController = TextEditingController(text: group['name']);
    final descController = TextEditingController(text: group['description'] ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text(
          'Edit Group',
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
            child: const Text('Save', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      try {
        await ApiService.updateGroup(
          widget.groupId,
          name: nameController.text.trim(),
          description: descController.text.trim().isEmpty ? null : descController.text.trim(),
        );
        _refreshGroup();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Group updated')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update group: $e')),
          );
        }
      }
    }
  }

  Future<void> _confirmDelete() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text(
          'Delete Group',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          'Are you sure you want to delete this group? Meetings will not be deleted, just ungrouped.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      try {
        await ApiService.deleteGroup(widget.groupId);
        if (mounted) {
          Navigator.pop(context, true); // Return to previous screen
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete group: $e')),
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Group Details',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppColors.textPrimary),
            color: AppColors.cardBackground,
            onSelected: (value) async {
              final group = await _groupFuture;
              if (value == 'edit') {
                _showEditDialog(group);
              } else if (value == 'delete') {
                _confirmDelete();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'edit',
                child: Text('Edit Group', style: TextStyle(color: AppColors.textPrimary)),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Delete Group', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _groupFuture,
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
                  Text(
                    'Failed to load group',
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    snapshot.error.toString(),
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _refreshGroup,
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

          final group = snapshot.data!;
          final meetings = group['meetings'] as List? ?? [];

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Group Info Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.cardBackground,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group['name'] ?? 'Unnamed Group',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (group['description'] != null && group['description'].toString().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          group['description'],
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Icon(Icons.folder, color: AppColors.accent, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            '${meetings.length} meeting${meetings.length == 1 ? '' : 's'}',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Chat Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => GroupChatScreen(
                            groupId: widget.groupId,
                            groupName: group['name'] ?? 'Group',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('Chat with Group'),
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
                const SizedBox(height: 24),

                // Meetings Section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Meetings',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${meetings.length}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if (meetings.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: AppColors.cardBackground,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.folder_open,
                          color: AppColors.textSecondary.withOpacity(0.5),
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No meetings in this group yet',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ...meetings.map((meeting) => _MeetingCard(
                        meeting: meeting,
                        groupId: widget.groupId,
                        onRemoved: _refreshGroup,
                      )),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MeetingCard extends StatelessWidget {
  final Map<String, dynamic> meeting;
  final String groupId;
  final VoidCallback onRemoved;

  const _MeetingCard({
    required this.meeting,
    required this.groupId,
    required this.onRemoved,
  });

  String _statusLabel(String status) {
    switch (status) {
      case 'uploaded':
        return 'Uploaded';
      case 'transcribing':
        return 'Transcribing';
      case 'transcribed':
        return 'Transcribed';
      case 'analyzing':
        return 'Analyzing';
      case 'completed':
        return 'Completed';
      case 'failed':
        return 'Failed';
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'uploaded':
        return Colors.blue;
      case 'transcribing':
        return Colors.amber;
      case 'transcribed':
        return Colors.orange;
      case 'analyzing':
        return Colors.purple;
      case 'completed':
        return Colors.green;
      case 'failed':
        return Colors.red;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = meeting['status'] as String? ?? 'unknown';
    final title = meeting['title'] as String? ?? 'Untitled Meeting';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _statusColor(status).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _statusLabel(status),
                  style: TextStyle(
                    color: _statusColor(status),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
          color: AppColors.cardBackground,
          onSelected: (value) async {
            if (value == 'view') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SummaryScreen(meetingId: meeting['id']),
                ),
              );
            } else if (value == 'remove') {
              try {
                await ApiService.removeMeetingFromGroup(groupId, meeting['id']);
                onRemoved();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Meeting removed from group')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to remove meeting: $e')),
                  );
                }
              }
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'view',
              child: Text('View Details', style: TextStyle(color: AppColors.textPrimary)),
            ),
            const PopupMenuItem(
              value: 'remove',
              child: Text('Remove from Group', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SummaryScreen(meetingId: meeting['id']),
            ),
          );
        },
      ),
    );
  }
}
