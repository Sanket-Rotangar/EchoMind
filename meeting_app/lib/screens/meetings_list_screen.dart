import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/api_service.dart';
import '../core/theme.dart';
import '../design_system/bento_tile.dart';
import 'summary_screen.dart';

class MeetingsListScreen extends StatefulWidget {
  const MeetingsListScreen({super.key});

  @override
  State<MeetingsListScreen> createState() => MeetingsListScreenState();
}

class MeetingsListScreenState extends State<MeetingsListScreen>
    with AutomaticKeepAliveClientMixin {
  static const int _pageSize = 8;
  final List<dynamic> _meetings = [];
  int _offset = 0;
  bool _hasMore = true;
  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadInitialMeetings();
  }

  Future<void> reloadMeetings() => _loadInitialMeetings();

  Future<void> _onRefresh() async {
    setState(() {
      _offset = 0;
      _hasMore = true;
      _error = null;
      _meetings.clear();
    });

    try {
      final freshBatch = await ApiService.getMeetings(
        offset: 0,
        limit: _pageSize,
      );

      if (!mounted) return;

      setState(() {
        _meetings.addAll(freshBatch);
        _hasMore = freshBatch.length >= _pageSize;
        _isInitialLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString();
        _isInitialLoading = false;
      });
    }
  }

  Future<void> _loadInitialMeetings() async {
    setState(() {
      _isInitialLoading = true;
      _error = null;
      _offset = 0;
      _hasMore = true;
      _meetings.clear();
    });

    try {
      final firstPage = await ApiService.getMeetings(
        offset: 0,
        limit: _pageSize,
      );

      if (!mounted) return;

      setState(() {
        _meetings.addAll(firstPage);
        _hasMore = firstPage.length >= _pageSize;
        _isInitialLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString();
        _isInitialLoading = false;
      });
    }
  }

  Future<void> _loadMoreMeetings() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);

    final nextOffset = _offset + _pageSize;

    try {
      final nextBatch = await ApiService.getMeetings(
        offset: nextOffset,
        limit: _pageSize,
      );

      if (!mounted) return;

      setState(() {
        _offset = nextOffset;
        _meetings.addAll(nextBatch);
        _hasMore = nextBatch.length >= _pageSize;
        _isLoadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isLoadingMore = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load older meetings: $error')),
      );
    }
  }

  String _formatDate(String? createdAt) {
    if (createdAt == null || createdAt.isEmpty) {
      return 'Unknown date';
    }

    final parsed = DateTime.tryParse(createdAt);
    if (parsed == null) {
      return createdAt;
    }

    const monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    final local = parsed.toLocal();
    final month = monthNames[local.month - 1];
    final hour24 = local.hour;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = hour24 >= 12 ? 'PM' : 'AM';
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;

    final day = local.day.toString().padLeft(2, '0');

    return '$month $day, ${local.year} • $hour12:$minute $suffix';
  }

  Widget _buildStatusBadge(String status) {
    if (status == 'uploaded') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.blue.withOpacity(0.45)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_upload, size: 14, color: Colors.blue),
            SizedBox(width: 6),
            Text(
              'Uploaded',
              style: TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    if (status == 'transcribing') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.yellow.withOpacity(0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.yellow.withOpacity(0.45)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoActivityIndicator(radius: 7),
            SizedBox(width: 8),
            Text(
              'Transcribing',
              style: TextStyle(
                color: Colors.yellow,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    if (status == 'transcribed') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.orange.withOpacity(0.45)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined, size: 14, color: Colors.orange),
            SizedBox(width: 6),
            Text(
              'Transcribed',
              style: TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    if (status == 'analyzing') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.purple.withOpacity(0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.purple.withOpacity(0.45)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoActivityIndicator(radius: 7),
            SizedBox(width: 8),
            Text(
              'Analyzing',
              style: TextStyle(
                color: Colors.purple,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    if (status == 'completed') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.green.withOpacity(0.45)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 14, color: Colors.green),
            SizedBox(width: 6),
            Text(
              'Completed',
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.red.withOpacity(0.45)),
      ),
      child: const Text(
        'Failed',
        style: TextStyle(
          color: Colors.red,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // App Logo Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Row(
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
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'Your Meetings',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Text(
              'All your recorded meetings and summaries',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: _isInitialLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primaryPeach,
                    ),
                  )
                : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text(
                        'Unable to load meetings: $_error',
                        style: const TextStyle(color: AppColors.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : _meetings.isEmpty
                ? const Center(
                    child: Text(
                      'No meetings yet.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _onRefresh,
                    color: AppColors.primaryPeach,
                    backgroundColor: AppColors.surface,
                    child: CustomScrollView(
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.all(20),
                          sliver: SliverGrid(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              childAspectRatio: 0.85,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final meeting = _meetings[index] as Map<String, dynamic>;
                                final title = (meeting['title'] ?? 'Untitled Meeting').toString();
                                final createdAt = meeting['created_at']?.toString();
                                final status = (meeting['status'] ?? 'uploaded').toString().toLowerCase();
                                final meetingId = meeting['id']?.toString();

                                return BentoTile(
                                  showGradientBorder: status == 'completed',
                                  onTap: meetingId != null
                                      ? () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => SummaryScreen(meetingId: meetingId),
                                            ),
                                          );
                                        }
                                      : null,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Status Badge
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          gradient: _getStatusGradient(status),
                                          borderRadius: BorderRadius.circular(12),
                                          boxShadow: [
                                            BoxShadow(
                                              color: _getStatusColor(status).withOpacity(0.3),
                                              blurRadius: 8,
                                            ),
                                          ],
                                        ),
                                        child: Text(
                                          status.toUpperCase(),
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                      
                                      const SizedBox(height: 16),
                                      
                                      // Title
                                      Expanded(
                                        child: Text(
                                          title,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textPrimary,
                                            height: 1.3,
                                          ),
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      
                                      const SizedBox(height: 12),
                                      
                                      // Date
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.access_time,
                                            size: 14,
                                            color: AppColors.textSecondary,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              _formatDate(createdAt),
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: AppColors.textSecondary,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                              childCount: _meetings.length,
                            ),
                          ),
                        ),
                        
                        // Load More Button
                        if (_hasMore)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 24),
                              child: Center(
                                child: TextButton(
                                  onPressed: _isLoadingMore ? null : _loadMoreMeetings,
                                  child: Text(
                                    _isLoadingMore ? 'Loading...' : 'Load older meetings...',
                                    style: const TextStyle(
                                      color: AppColors.primaryPeach,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
  
  LinearGradient _getStatusGradient(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return const LinearGradient(
          colors: [Color(0xFF10B981), Color(0xFF059669)],
        );
      case 'processing':
      case 'analyzing':
      case 'transcribing':
        return const LinearGradient(
          colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
        );
      case 'failed':
        return const LinearGradient(
          colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
        );
      default:
        return AppColors.primaryGradient;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return AppColors.statusCompleted;
      case 'processing':
      case 'analyzing':
      case 'transcribing':
        return AppColors.statusProcessing;
      case 'failed':
        return AppColors.statusFailed;
      default:
        return AppColors.primaryAccent;
    }
  }
}
