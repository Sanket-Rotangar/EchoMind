import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../core/api_service.dart';
import '../core/theme.dart';

class HomeRecordScreen extends StatefulWidget {
  final VoidCallback onUploadComplete;

  const HomeRecordScreen({super.key, required this.onUploadComplete});

  @override
  State<HomeRecordScreen> createState() => _HomeRecordScreenState();
}

class _HomeRecordScreenState extends State<HomeRecordScreen>
    with SingleTickerProviderStateMixin {
  bool _isRecording = false;
  bool _isProcessing = false;
  late AnimationController _pulseController;
  final AudioRecorder _audioRecorder = AudioRecorder();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_isProcessing) return;

    if (_isRecording) {
      setState(() => _isRecording = false);

      setState(() => _isProcessing = true);

      try {
        final filePath = await _audioRecorder.stop();

        if (filePath == null || filePath.isEmpty) {
          throw Exception('Unable to read recorded audio file');
        }

        final result = await ApiService.processMeetingAudio(filePath);

        if (!mounted) return;

        setState(() => _isProcessing = false);

        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Meeting uploaded! Processing in background.'),
            ),
          );
          widget.onUploadComplete();
        } else {
          throw Exception('Upload accepted but response was invalid');
        }
      } catch (error) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to process audio: $error')),
        );

        setState(() => _isProcessing = false);
      }
    } else {
      try {
        if (!await _audioRecorder.hasPermission()) {
          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission is required.')),
          );
          return;
        }

        final dir = await getTemporaryDirectory();
        final filePath =
            '${dir.path}/meeting_${DateTime.now().millisecondsSinceEpoch}.m4a';

        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 128000,
            sampleRate: 44100,
          ),
          path: filePath,
        );

        if (!mounted) return;

        setState(() => _isRecording = true);
      } catch (error) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start recording: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
            Text(
              'Start your meeting\nin seconds',
              style: Theme.of(context).textTheme.displayLarge,
            ),
            const SizedBox(height: 16),
            Text(
              'Bring your team together and let AI handle the documentation.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const Spacer(),
            Center(
              child: GestureDetector(
                onTap: _toggleRecording,
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          if (_isRecording)
                            BoxShadow(
                              color: AppColors.primaryPeach.withOpacity(
                                0.5 * _pulseController.value,
                              ),
                              blurRadius: 60,
                              spreadRadius: 15 * _pulseController.value,
                            ),
                        ],
                        gradient: RadialGradient(
                          colors: _isRecording
                              ? [
                                  AppColors.primaryPeach,
                                  AppColors.primaryPeach.withOpacity(0.6),
                                ]
                              : [AppColors.surface, AppColors.background],
                        ),
                        border: Border.all(
                          color: _isRecording
                              ? AppColors.primaryPeach
                              : AppColors.border,
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: _isProcessing
                            ? const CircularProgressIndicator(
                                color: AppColors.primaryPeach,
                              )
                            : Icon(
                                _isRecording
                                    ? Icons.stop_rounded
                                    : Icons.mic_none,
                                size: 64,
                                color: AppColors.textPrimary,
                              ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 32),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  _isProcessing
                      ? 'Extracting intelligence...'
                      : (_isRecording
                            ? 'Listening to meeting...'
                            : 'Tap to begin recording'),
                  style: TextStyle(
                    color: _isRecording ? AppColors.primaryPeach : AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
