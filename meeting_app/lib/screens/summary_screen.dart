import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../core/api_service.dart';
import '../core/theme.dart';
import '../services/pdf_generator.dart';
import '../design_system/bento_tile.dart';
import '../design_system/glow_icon.dart';
import '../design_system/glass_card.dart';
import '../design_system/colors.dart' as DesignColors;
import 'group_detail_screen.dart';

class SummaryScreen extends StatefulWidget {
  final String meetingId;

  const SummaryScreen({super.key, required this.meetingId});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  late Future<Map<String, dynamic>> _meetingFuture;

  @override
  void initState() {
    super.initState();
    _meetingFuture = ApiService.getMeetingDetails(widget.meetingId);
  }

  void _refreshMeeting() {
    setState(() {
      _meetingFuture = ApiService.getMeetingDetails(widget.meetingId);
    });
  }

  Future<void> _downloadPdf(BuildContext context) async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: AppColors.primaryPeach),
        ),
      );

      // Get meeting data
      final meeting = await _meetingFuture;
      
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      final title = meeting['title']?.toString() ?? 'Untitled Meeting';
      final createdAt = meeting['created_at']?.toString() ?? '';
      final intelligenceData = meeting['intelligence_data'] as Map<String, dynamic>? ?? {};
      final transcript = meeting['transcript_text']?.toString();

      // Generate PDF
      final pdfFile = await PdfGenerator.generateMeetingMinutes(
        title: title,
        createdAt: createdAt,
        intelligenceData: intelligenceData,
        transcript: transcript,
      );

      if (!mounted) return;

      // Show share/save dialog
      await Printing.sharePdf(
        bytes: await pdfFile.readAsBytes(),
        filename: 'meeting_minutes_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Meeting minutes ready to share')),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog if still open
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate PDF: $e')),
        );
      }
    }
  }

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

  String _formatDateTime(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    final parsed = DateTime.tryParse(dateStr);
    if (parsed == null) return dateStr;

    final local = parsed.toLocal();
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final month = months[local.month - 1];
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');

    return '$month $day, ${local.year} at $hour:$minute';
  }

  Future<void> _showAddToGroupDialog() async {
    try {
      final groups = await ApiService.getGroups();
      
      if (!mounted) return;

      if (groups.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No groups available. Create a group first from the Groups tab.')),
        );
        return;
      }

      final selectedGroup = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text(
            'Add to Group',
            style: TextStyle(color: AppColors.textPrimary),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: groups.length,
              itemBuilder: (context, index) {
                final group = groups[index];
                return ListTile(
                  leading: const Icon(Icons.folder, color: AppColors.accent),
                  title: Text(
                    group['name'] ?? 'Unnamed Group',
                    style: const TextStyle(color: AppColors.textPrimary),
                  ),
                  onTap: () => Navigator.pop(context, group),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
            ),
          ],
        ),
      );

      if (selectedGroup != null && mounted) {
        try {
          await ApiService.addMeetingToGroup(selectedGroup['id'], widget.meetingId);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Added to ${selectedGroup['name']}')),
            );
            _refreshMeeting();
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to add to group: $e')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load groups: $e')),
        );
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
          'Meeting Summary',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.primaryPeach),
            onPressed: _refreshMeeting,
          ),
          IconButton(
            icon: const Icon(Icons.share, color: AppColors.primaryPeach),
            onPressed: () => _downloadPdf(context),
            tooltip: 'Share Minutes',
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _meetingFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.primaryPeach),
                  SizedBox(height: 16),
                  Text(
                    'Loading meeting details...',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                  ),
                ],
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load meeting',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${snapshot.error}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _refreshMeeting,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryPeach,
                        foregroundColor: Colors.black,
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          final data = snapshot.data ?? {};
          final status = (data['status'] ?? 'uploaded').toString().toLowerCase();
          final title = (data['title'] ?? 'Untitled Meeting').toString();
          final failureReason = (data['failure_reason'] ?? '').toString();
          final groupId = data['group_id']?.toString();

          final intelligenceData = data['intelligence_data'] is Map<String, dynamic>
              ? data['intelligence_data'] as Map<String, dynamic>
              : <String, dynamic>{};

          final bottomLine = (intelligenceData['bottom_line'] ?? '').toString();

          final rawActions = intelligenceData['action_matrix'] ?? intelligenceData['action_items'];
          final actionMatrix = rawActions is List
              ? rawActions.whereType<Map<dynamic, dynamic>>().toList()
              : [];

          final rawDecisions = intelligenceData['decisions_register'] ?? intelligenceData['decisions_made'];
          final decisions = rawDecisions is List
              ? rawDecisions.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
              : <String>[];

          final rawRisks = intelligenceData['risks_and_blockers'] ?? intelligenceData['blockers'];
          final risks = rawRisks is List
              ? rawRisks.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
              : <String>[];

          final rawMetrics = intelligenceData['key_metrics'];
          final metrics = rawMetrics is List
              ? rawMetrics.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
              : <String>[];

          final stateEvents = (data['meeting_state_events'] is List)
              ? (data['meeting_state_events'] as List).whereType<Map<String, dynamic>>().toList()
              : <Map<String, dynamic>>[];

          stateEvents.sort((a, b) {
            final aTime = (a['created_at'] ?? '').toString();
            final bTime = (b['created_at'] ?? '').toString();
            return bTime.compareTo(aTime);
          });

          return RefreshIndicator(
            onRefresh: () async => _refreshMeeting(),
            color: AppColors.primaryPeach,
            backgroundColor: AppColors.surface,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Add/Remove from Group Button (prominent)
                  if (status == 'completed')
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 16),
                      child: groupId == null
                          ? ElevatedButton.icon(
                              onPressed: _showAddToGroupDialog,
                              icon: const Icon(Icons.folder_outlined, size: 24),
                              label: const Text('Add to Group', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryPeach,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            )
                          : ElevatedButton.icon(
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    backgroundColor: AppColors.surface,
                                    title: const Text('Remove from Group', style: TextStyle(color: AppColors.textPrimary)),
                                    content: const Text(
                                      'Remove this meeting from its group?',
                                      style: TextStyle(color: AppColors.textSecondary),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context, false),
                                        child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.pop(context, true),
                                        child: const Text('Remove', style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                );
                                
                                if (confirm == true && mounted) {
                                  try {
                                    await ApiService.removeMeetingFromGroup(groupId, widget.meetingId);
                                    _refreshMeeting();
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Removed from group')),
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Failed to remove: $e')),
                                      );
                                    }
                                  }
                                }
                              },
                              icon: const Icon(Icons.folder_off, size: 24),
                              label: const Text('Remove from Group', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.withOpacity(0.2),
                                foregroundColor: Colors.red,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                    ),

                  // Group Info (if meeting is in a group)
                  if (groupId != null) ...[
                    FutureBuilder<Map<String, dynamic>>(
                      future: ApiService.getGroupDetail(groupId),
                      builder: (context, groupSnapshot) {
                        if (groupSnapshot.hasData) {
                          final group = groupSnapshot.data!;
                          final groupMeetings = (group['meetings'] as List?) ?? [];
                          return _buildCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.folder, color: AppColors.primaryPeach, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Part of: ${group['name']}',
                                        style: const TextStyle(
                                          color: AppColors.primaryPeach,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => GroupDetailScreen(groupId: groupId),
                                          ),
                                        );
                                      },
                                      child: const Text('View Group'),
                                    ),
                                  ],
                                ),
                                if (groupMeetings.length > 1) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    '${groupMeetings.length} meetings in this series',
                                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Title and Status Card
                  _buildCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildStatusChip(status),
                        if (status == 'failed' && failureReason.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Error: $failureReason',
                            style: const TextStyle(color: Colors.red, fontSize: 13),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Processing status message
                  if (status != 'completed' && status != 'failed') ...[
                    const SizedBox(height: 16),
                    _buildCard(
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primaryPeach,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Meeting is being processed. Pull down to refresh.',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Bottom Line / Executive Summary
                  if (bottomLine.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _buildSectionHeader('Executive Summary', Icons.lightbulb_outline),
                    const SizedBox(height: 12),
                    _buildCard(
                      child: Text(
                        bottomLine,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          height: 1.6,
                        ),
                      ),
                    ),
                  ],

                  // Key Metrics
                  if (metrics.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _buildSectionHeader('Key Metrics', Icons.analytics_outlined),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: metrics.map((metric) => _buildMetricChip(metric)).toList(),
                    ),
                  ],

                  // Action Items
                  if (actionMatrix.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _buildSectionHeader('Action Items', Icons.task_alt_outlined),
                    const SizedBox(height: 12),
                    ...actionMatrix.map((action) => _buildActionItem(action)),
                  ],

                  // Decisions
                  if (decisions.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _buildSectionHeader('Decisions Made', Icons.gavel_outlined),
                    const SizedBox(height: 12),
                    ...decisions.map((decision) => _buildListItem(decision, Icons.check_circle_outline, Colors.green)),
                  ],

                  // Risks & Blockers
                  if (risks.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _buildSectionHeader('Risks & Blockers', Icons.warning_amber_outlined),
                    const SizedBox(height: 12),
                    ...risks.map((risk) => _buildListItem(risk, Icons.warning_amber_rounded, Colors.orange)),
                  ],

                  // Pipeline Events (Collapsible)
                  if (stateEvents.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _buildSectionHeader('Processing Timeline', Icons.timeline_outlined),
                    const SizedBox(height: 12),
                    _buildCard(
                      child: Column(
                        children: stateEvents.take(5).map((event) {
                          final stage = (event['stage'] ?? 'unknown').toString();
                          final createdAt = _formatDateTime(event['created_at']?.toString());
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: _statusColor(stage),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _statusLabel(stage),
                                        style: const TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      if (createdAt.isNotEmpty)
                                        Text(
                                          createdAt,
                                          style: const TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 12,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],

                  // Empty state
                  if (intelligenceData.isEmpty && status == 'completed') ...[
                    const SizedBox(height: 24),
                    _buildCard(
                      child: const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Column(
                            children: [
                              Icon(Icons.hourglass_empty, color: AppColors.textSecondary, size: 48),
                              SizedBox(height: 16),
                              Text(
                                'No insights available',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'This meeting may not have generated any actionable insights.',
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 40),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return BentoTile(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      child: child,
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        GlowIcon(
          icon: icon,
          size: 24,
          color: DesignColors.AppColors.primaryAccent,
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusChip(String status) {
    final color = _statusColor(status);
    final gradient = _getStatusGradient(status);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == 'transcribing' || status == 'analyzing')
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(
                status == 'completed' ? Icons.check_circle : 
                status == 'failed' ? Icons.error : Icons.circle,
                color: Colors.white,
                size: 16,
              ),
            ),
          Text(
            _statusLabel(status),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  LinearGradient _getStatusGradient(String status) {
    switch (status) {
      case 'completed':
        return const LinearGradient(
          colors: [Color(0xFF10B981), Color(0xFF059669)],
        );
      case 'processing':
      case 'transcribing':
      case 'analyzing':
        return const LinearGradient(
          colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
        );
      case 'failed':
        return const LinearGradient(
          colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
        );
      default:
        return DesignColors.AppColors.primaryGradient;
    }
  }

  Widget _buildMetricChip(String metric) {
    return BentoTile(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlowIcon(
            icon: Icons.insights,
            size: 18,
            color: DesignColors.AppColors.secondaryAccent,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              metric,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionItem(Map<dynamic, dynamic> action) {
    final assignee = (action['assignee'] ?? 'Unassigned').toString();
    final task = (action['task'] ?? '').toString();
    final deadline = action['deadline']?.toString();
    final priority = (action['priority'] ?? '').toString().toLowerCase();

    Color priorityColor = AppColors.textSecondary;
    if (priority == 'high') priorityColor = Colors.red;
    if (priority == 'medium') priorityColor = Colors.orange;
    if (priority == 'low') priorityColor = Colors.green;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _buildCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.primaryPeach.withOpacity(0.2),
                  child: Text(
                    assignee.isNotEmpty ? assignee[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: AppColors.primaryPeach,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    assignee,
                    style: const TextStyle(
                      color: AppColors.primaryPeach,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (priority.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: priorityColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      priority.toUpperCase(),
                      style: TextStyle(
                        color: priorityColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              task,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            if (deadline != null && deadline.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.schedule, color: AppColors.textSecondary, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    deadline,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildListItem(String text, IconData icon, Color iconColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _buildCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
