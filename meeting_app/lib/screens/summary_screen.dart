import 'package:flutter/material.dart';

import '../core/api_service.dart';
import '../core/theme.dart';
import 'chat_screen.dart';

class SummaryScreen extends StatefulWidget {
  final String meetingId;

  const SummaryScreen({super.key, required this.meetingId});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  late Future<Map<String, dynamic>> _meetingFuture;
  bool _isRegenerating = false;

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

  void _openMeetingAssistant(String meetingTitle) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          meetingId: widget.meetingId,
          meetingTitle: meetingTitle,
        ),
      ),
    );
  }

  Map<String, dynamic> _asStringMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return <String, dynamic>{};
  }

  bool _canRegenerate(String status) {
    return status == 'completed' || status == 'failed';
  }

  Future<void> _regenerateMeeting(String title, String status) async {
    if (_isRegenerating || !_canRegenerate(status)) {
      return;
    }

    final approved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text(
            'Regenerate Meeting?',
            style: TextStyle(color: AppColors.textPrimary),
          ),
          content: Text(
            'This reruns transcription and analysis for "$title" using the same uploaded audio.',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryPeach,
                foregroundColor: Colors.black,
              ),
              child: const Text('Regenerate'),
            ),
          ],
        );
      },
    );

    if (approved != true) {
      return;
    }

    setState(() => _isRegenerating = true);
    try {
      await ApiService.regenerateMeeting(widget.meetingId);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Regeneration started. Processing in background.'),
        ),
      );
      _refreshMeeting();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to regenerate meeting: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isRegenerating = false);
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
      case 'regenerate_requested':
        return 'Regenerate Requested';
      case 'transcript_snapshot':
        return 'Transcript Snapshot Saved';
      case 'analysis_snapshot':
        return 'Analysis Snapshot Saved';
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
              ? rawDecisions.map((e) => e.toString()).toList()
              : <String>[];

          final rawRisks = intelligenceData['risks_and_blockers'] ?? intelligenceData['blockers'];
          final risks = rawRisks is List
              ? rawRisks.map((e) => e.toString()).toList()
              : <String>[];

          final rawMetrics = intelligenceData['key_metrics'];
          final metrics = rawMetrics is List
              ? rawMetrics.map((e) => e.toString()).toList()
              : <String>[];

          final stateEvents = (data['meeting_state_events'] is List)
              ? (data['meeting_state_events'] as List).whereType<Map<String, dynamic>>().toList()
              : <Map<String, dynamic>>[];

          stateEvents.sort((a, b) {
            final aTime = (a['created_at'] ?? '').toString();
            final bTime = (b['created_at'] ?? '').toString();
            return bTime.compareTo(aTime);
          });

          final transcriptSnapshots = stateEvents
              .where((event) => (event['stage'] ?? '').toString() == 'transcript_snapshot')
              .toList();
          final analysisSnapshots = stateEvents
              .where((event) => (event['stage'] ?? '').toString() == 'analysis_snapshot')
              .toList();

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

                  const SizedBox(height: 12),
                  _buildCard(
                    child: Row(
                      children: [
                        const Icon(
                          Icons.auto_awesome,
                          color: AppColors.primaryPeach,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Ask AI about this meeting',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _openMeetingAssistant(title),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryPeach,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.chat_bubble_outline, size: 16),
                          label: const Text(
                            'Open Chat',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (_canRegenerate(status)) ...[
                    const SizedBox(height: 12),
                    _buildCard(
                      child: Row(
                        children: [
                          const Icon(
                            Icons.restart_alt,
                            color: AppColors.primaryPeach,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Regenerate transcript and summary',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: _isRegenerating
                                ? null
                                : () => _regenerateMeeting(title, status),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryPeach,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: _isRegenerating
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.black,
                                    ),
                                  )
                                : const Icon(Icons.refresh, size: 16),
                            label: Text(
                              _isRegenerating ? 'Starting...' : 'Regenerate',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

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

                  if (transcriptSnapshots.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _buildSectionHeader(
                      'Transcript History',
                      Icons.description_outlined,
                    ),
                    const SizedBox(height: 12),
                    ...transcriptSnapshots.take(3).map((event) {
                      final details = _asStringMap(event['details']);
                      final runId = (details['run_id'] ?? 'unknown').toString();
                      final transcriptText =
                          (details['transcript_text'] ?? '').toString();
                      final createdAt = _formatDateTime(
                        event['created_at']?.toString(),
                      );
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Run: $runId',
                                style: const TextStyle(
                                  color: AppColors.primaryPeach,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (createdAt.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  createdAt,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                              if (transcriptText.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Text(
                                  transcriptText,
                                  maxLines: 8,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 13,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }),
                  ],

                  if (analysisSnapshots.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _buildSectionHeader('Analysis History', Icons.psychology_alt),
                    const SizedBox(height: 12),
                    ...analysisSnapshots.take(3).map((event) {
                      final details = _asStringMap(event['details']);
                      final runId = (details['run_id'] ?? 'unknown').toString();
                      final createdAt = _formatDateTime(
                        event['created_at']?.toString(),
                      );
                      final summary = (details['summary'] ?? '').toString();
                      final intelligence = _asStringMap(
                        details['intelligence_data'],
                      );
                      final actionCount =
                          (intelligence['action_matrix'] is List)
                          ? (intelligence['action_matrix'] as List).length
                          : 0;
                      final decisionsCount =
                          (intelligence['decisions_register'] is List)
                          ? (intelligence['decisions_register'] as List).length
                          : 0;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Run: $runId',
                                style: const TextStyle(
                                  color: AppColors.primaryPeach,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (createdAt.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  createdAt,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                              if (summary.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Text(
                                  summary,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 13,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 10),
                              Text(
                                'Action items: $actionCount • Decisions: $decisionsCount',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primaryPeach, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusChip(String status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == 'transcribing' || status == 'analyzing')
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: color,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(
                status == 'completed' ? Icons.check_circle : 
                status == 'failed' ? Icons.error : Icons.circle,
                color: color,
                size: 14,
              ),
            ),
          Text(
            _statusLabel(status),
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricChip(String metric) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.insights, color: AppColors.primaryPeach, size: 16),
          const SizedBox(width: 6),
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
