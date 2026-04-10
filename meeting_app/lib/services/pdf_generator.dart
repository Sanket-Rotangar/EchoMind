import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PdfGenerator {
  static Future<File> generateMeetingMinutes({
    required String title,
    required String createdAt,
    required Map<String, dynamic> intelligenceData,
    required String? transcript,
  }) async {
    final pdf = pw.Document();

    // Load logo
    final ByteData logoData = await rootBundle.load('assets/images/logo.png');
    final Uint8List logoBytes = logoData.buffer.asUint8List();
    final logo = pw.MemoryImage(logoBytes);

    // Parse intelligence data
    final bottomLine = intelligenceData['bottom_line']?.toString() ?? '';
    final decisions = (intelligenceData['decisions_register'] as List?)
            ?.map((e) => e.toString())
            .where((s) => s.isNotEmpty)
            .toList() ??
        [];
    final actions = (intelligenceData['action_matrix'] as List?) ?? [];
    final risks = (intelligenceData['risks_and_blockers'] as List?)
            ?.map((e) => e.toString())
            .where((s) => s.isNotEmpty)
            .toList() ??
        [];
    final metrics = (intelligenceData['key_metrics'] as List?)
            ?.map((e) => e.toString())
            .where((s) => s.isNotEmpty)
            .toList() ??
        [];

    // Format date
    String formattedDate = 'Unknown Date';
    try {
      final parsed = DateTime.parse(createdAt);
      formattedDate = DateFormat('MMMM dd, yyyy • hh:mm a').format(parsed.toLocal());
    } catch (e) {
      formattedDate = createdAt;
    }

    // Define colors - professional document style
    final primaryColor = PdfColor.fromHex('#000000'); // Black
    final accentColor = PdfColor.fromHex('#1a1a1a'); // Dark gray
    final textPrimary = PdfColor.fromHex('#000000'); // Black
    final textSecondary = PdfColor.fromHex('#4a4a4a'); // Medium gray
    final dividerColor = PdfColor.fromHex('#cccccc'); // Light gray

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(60),
          theme: pw.ThemeData.withFont(
            base: await PdfGoogleFonts.crimsonTextRegular(),
            bold: await PdfGoogleFonts.crimsonTextBold(),
          ),
        ),
        build: (context) => [
          // Header with logo - centered
          pw.Center(
            child: pw.Column(
              children: [
                pw.Container(
                  width: 60,
                  height: 60,
                  child: pw.Image(logo),
                ),
                pw.SizedBox(height: 12),
                pw.Text(
                  'EchoMind',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: textPrimary,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 30),
          pw.Divider(color: dividerColor, thickness: 1),
          pw.SizedBox(height: 30),

          // Title section - centered
          pw.Center(
            child: pw.Column(
              children: [
                pw.Text(
                  'MEETING MINUTES',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: textSecondary,
                    letterSpacing: 3,
                  ),
                ),
                pw.SizedBox(height: 16),
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                    color: textPrimary,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 12),
                pw.Text(
                  formattedDate,
                  style: pw.TextStyle(
                    fontSize: 11,
                    color: textSecondary,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 40),

          // Executive Summary
          if (bottomLine.isNotEmpty) ...[
            _buildSectionHeader('EXECUTIVE SUMMARY', textPrimary),
            pw.SizedBox(height: 12),
            pw.Text(
              bottomLine,
              style: pw.TextStyle(
                fontSize: 12,
                color: textPrimary,
                height: 1.8,
              ),
              textAlign: pw.TextAlign.justify,
            ),
            pw.SizedBox(height: 24),
          ],

          // Key Metrics
          if (metrics.isNotEmpty) ...[
            _buildSectionHeader('KEY METRICS', textPrimary),
            pw.SizedBox(height: 12),
            ...metrics.asMap().entries.map((entry) {
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6, left: 20),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      '${entry.key + 1}. ',
                      style: pw.TextStyle(
                        fontSize: 11,
                        color: textPrimary,
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Text(
                        entry.value,
                        style: pw.TextStyle(
                          fontSize: 11,
                          color: textPrimary,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            pw.SizedBox(height: 24),
          ],

          // Action Items
          if (actions.isNotEmpty) ...[
            _buildSectionHeader('ACTION ITEMS', textPrimary),
            pw.SizedBox(height: 12),
            ...actions.asMap().entries.map((entry) {
              if (entry.value is! Map) return pw.SizedBox();
              final action = entry.value as Map;
              final assignee = action['assignee']?.toString() ?? 'Unassigned';
              final task = action['task']?.toString() ?? '';
              final deadline = action['deadline']?.toString();

              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 16, left: 20),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          '${entry.key + 1}. ',
                          style: pw.TextStyle(
                            fontSize: 11,
                            color: textPrimary,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                task,
                                style: pw.TextStyle(
                                  fontSize: 11,
                                  color: textPrimary,
                                  height: 1.5,
                                ),
                              ),
                              pw.SizedBox(height: 4),
                              pw.Text(
                                'Assignee: $assignee',
                                style: pw.TextStyle(
                                  fontSize: 10,
                                  color: textSecondary,
                                  fontStyle: pw.FontStyle.italic,
                                ),
                              ),
                              if (deadline != null && deadline.isNotEmpty)
                                pw.Text(
                                  'Deadline: $deadline',
                                  style: pw.TextStyle(
                                    fontSize: 10,
                                    color: textSecondary,
                                    fontStyle: pw.FontStyle.italic,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
            pw.SizedBox(height: 24),
          ],

          // Decisions Made
          if (decisions.isNotEmpty) ...[
            _buildSectionHeader('DECISIONS MADE', textPrimary),
            pw.SizedBox(height: 12),
            ...decisions.asMap().entries.map((entry) {
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8, left: 20),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      '${entry.key + 1}. ',
                      style: pw.TextStyle(
                        fontSize: 11,
                        color: textPrimary,
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Text(
                        entry.value,
                        style: pw.TextStyle(
                          fontSize: 11,
                          color: textPrimary,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            pw.SizedBox(height: 24),
          ],

          // Risks & Blockers
          if (risks.isNotEmpty) ...[
            _buildSectionHeader('RISKS & BLOCKERS', textPrimary),
            pw.SizedBox(height: 12),
            ...risks.asMap().entries.map((entry) {
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8, left: 20),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      '${entry.key + 1}. ',
                      style: pw.TextStyle(
                        fontSize: 11,
                        color: textPrimary,
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Text(
                        entry.value,
                        style: pw.TextStyle(
                          fontSize: 11,
                          color: textPrimary,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            pw.SizedBox(height: 24),
          ],

          // Transcript
          if (transcript != null && transcript.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Divider(color: dividerColor, thickness: 1),
            pw.SizedBox(height: 20),
            _buildSectionHeader('FULL TRANSCRIPT', textPrimary),
            pw.SizedBox(height: 12),
            pw.Text(
              transcript,
              style: pw.TextStyle(
                fontSize: 10,
                color: textSecondary,
                height: 1.7,
              ),
              textAlign: pw.TextAlign.justify,
            ),
          ],
        ],
        footer: (context) => pw.Column(
          children: [
            pw.Divider(color: dividerColor, thickness: 0.5),
            pw.SizedBox(height: 10),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'EchoMind Meeting Minutes',
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: textSecondary,
                  ),
                ),
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    // Save PDF
    final output = await getTemporaryDirectory();
    final file = File('${output.path}/meeting_minutes_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await pdf.save());

    return file;
  }

  static pw.Widget _buildSectionHeader(String title, PdfColor textPrimary) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: textPrimary,
            letterSpacing: 1.5,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Container(
          width: 60,
          height: 1.5,
          color: textPrimary,
        ),
      ],
    );
  }
}
