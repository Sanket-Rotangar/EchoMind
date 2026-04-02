import 'package:flutter/material.dart';

import '../core/api_service.dart';
import '../core/theme.dart';

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

  @override
  Widget build(BuildContext context) {
    if (widget.meetingId.isEmpty) {
      return const Center(
        child: Text(
          'Open a completed meeting from Home to view intelligence.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
          textAlign: TextAlign.center,
        ),
      );
    }

    return FutureBuilder<Map<String, dynamic>>(
      future: _meetingFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.primaryPeach),
                  SizedBox(height: 16),
                  Text(
                    'Retrieving intelligence...',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
                  ),
                ],
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                'Unable to load summary: ${snapshot.error}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final responseData = snapshot.data ?? <String, dynamic>{};
        final intelligenceData = responseData['intelligence_data'] is Map<String, dynamic>
            ? responseData['intelligence_data'] as Map<String, dynamic>
            : <String, dynamic>{};

        if (intelligenceData.isEmpty) {
          return const Center(
            child: Text(
              'No intelligence available for this meeting yet.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          );
        }

        final bottomLine = (intelligenceData['bottom_line'] ?? 'No executive summary provided.').toString();

        final rawActions = intelligenceData['action_matrix'] ?? intelligenceData['action_items'];
        final actionMatrix = rawActions is List ? rawActions.whereType<Map<dynamic, dynamic>>().toList() : [];

        final rawDecisions = intelligenceData['decisions_register'] ?? intelligenceData['decisions_made'];
        final decisions = rawDecisions is List ? rawDecisions.map((e) => e.toString()).toList() : <String>[];

        final rawRisks = intelligenceData['risks_and_blockers'] ?? intelligenceData['blockers'];
        final risks = rawRisks is List ? rawRisks.map((e) => e.toString()).toList() : <String>[];

        final rawMetrics = intelligenceData['key_metrics'];
        final metrics = rawMetrics is List ? rawMetrics.map((e) => e.toString()).toList() : <String>[];

        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              Text('Meeting Intelligence', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16.0),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.insights, color: AppColors.primaryPeach, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'The Bottom Line',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      bottomLine,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5, color: Colors.white),
                    ),
                  ],
                ),
              ),
              if (metrics.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('Key Metrics', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8.0,
                  runSpacing: 8.0,
                  children: metrics
                      .map(
                        (metric) => Chip(
                          label: Text(metric, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                          backgroundColor: AppColors.surface,
                          side: const BorderSide(color: AppColors.border),
                          avatar: const Icon(Icons.data_usage, size: 16, color: AppColors.primaryPeach),
                        ),
                      )
                      .toList(),
                ),
              ],
              if (risks.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('Risks & Blockers', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                ...risks.map(
                  (risk) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16.0),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: AppColors.primaryPeach, size: 20),
                        const SizedBox(width: 10),
                        Expanded(child: Text(risk, style: const TextStyle(color: AppColors.textPrimary, height: 1.4))),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Text('Action Matrix', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (actionMatrix.isEmpty)
                const Text('No specific tasks assigned.', style: TextStyle(color: AppColors.textSecondary))
              else
                ...actionMatrix.map(
                  (action) => Padding(
                    padding: const EdgeInsets.only(bottom: 10.0),
                    child: Container(
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16.0),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: AppColors.border,
                            child: Text(
                              (action['assignee'] ?? '?').toString().substring(0, 1).toUpperCase(),
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      (action['assignee'] ?? 'Unassigned').toString(),
                                      style: const TextStyle(
                                        color: AppColors.primaryPeach,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (action['deadline'] != null)
                                      Text(
                                        action['deadline'].toString(),
                                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  (action['task'] ?? '').toString(),
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 16,
                                    height: 1.4,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                ),
              if (decisions.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('Decisions Register', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                ...decisions.map(
                  (decision) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16.0),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check_circle_outline, color: AppColors.primaryPeach, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            decision,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              height: 1.4,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}
