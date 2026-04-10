import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../core/api_service.dart';
import '../core/theme.dart';
import '../design_system/glass_card.dart';
import '../design_system/neumorphic_button.dart';

class HomeRecordScreen extends StatefulWidget {
  final VoidCallback onUploadComplete;

  const HomeRecordScreen({super.key, required this.onUploadComplete});

  @override
  State<HomeRecordScreen> createState() => _HomeRecordScreenState();
}

class _HomeRecordScreenState extends State<HomeRecordScreen>
    with SingleTickerProviderStateMixin {
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isProcessing = false;
  late AnimationController _pulseController;
  final AudioRecorder _audioRecorder = AudioRecorder();
  final FlutterTts _flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _initializeTts();
  }

  Future<void> _initializeTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5); // Slower, more formal
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  Future<void> _playRecordingWarning() async {
    try {
      await _flutterTts.speak(
        "Kindly be informed, this conversation is being recorded."
      );
    } catch (e) {
      // Silently fail if TTS is not available
      debugPrint('TTS warning failed: $e');
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _audioRecorder.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  Future<void> _togglePause() async {
    if (!_isRecording || _isProcessing) return;

    try {
      if (_isPaused) {
        // Resume recording
        await _audioRecorder.resume();
        setState(() => _isPaused = false);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Recording resumed'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      } else {
        // Pause recording
        await _audioRecorder.pause();
        setState(() => _isPaused = true);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Recording paused'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to ${_isPaused ? 'resume' : 'pause'}: $error')),
        );
      }
    }
  }

  Future<void> _uploadAudioFile() async {
    if (_isProcessing || _isRecording) return;

    try {
      // Pick audio file
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        // User canceled the picker
        return;
      }

      final file = result.files.first;
      final filePath = file.path;

      if (filePath == null || filePath.isEmpty) {
        throw Exception('Unable to read selected audio file');
      }

      if (!mounted) return;

      setState(() => _isProcessing = true);

      // Show uploading message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Uploading audio file...'),
          duration: Duration(seconds: 2),
        ),
      );

      final uploadResult = await ApiService.processMeetingAudio(filePath);

      if (!mounted) return;

      setState(() => _isProcessing = false);

      if (uploadResult['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Audio uploaded! Processing in background.'),
          ),
        );
        widget.onUploadComplete();
      } else {
        throw Exception('Upload accepted but response was invalid');
      }
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload audio: $error')),
      );

      setState(() => _isProcessing = false);
    }
  }

  Future<void> _toggleRecording() async {
    if (_isProcessing) return;

    if (_isRecording) {
      setState(() {
        _isRecording = false;
        _isPaused = false;
      });

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
        
        // Play recording warning announcement
        _playRecordingWarning();
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
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryAccent.withOpacity(0.3),
                        blurRadius: 15,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ShaderMask(
                  shaderCallback: (bounds) => AppColors.primaryGradient.createShader(bounds),
                  child: const Text(
                    'EchoMind',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            const Text(
              'Start your meeting\nin seconds',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                height: 1.2,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Bring your team together and let AI handle the documentation.',
              style: TextStyle(
                color: AppColors.textSecondary.withOpacity(0.8),
                fontSize: 15,
                height: 1.5,
              ),
            ),
            const Spacer(),
            Center(
              child: Column(
                children: [
                  // Glowing Microphone Orb
                  GestureDetector(
                    onTap: _toggleRecording,
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Container(
                          width: 180,
                          height: 180,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: _isRecording
                                ? (_isPaused
                                    ? const LinearGradient(
                                        colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                                      )
                                    : AppColors.primaryGradient)
                                : null,
                            color: _isRecording ? null : AppColors.surface,
                            boxShadow: [
                              if (_isRecording && !_isPaused)
                                BoxShadow(
                                  color: AppColors.primaryAccent.withOpacity(
                                    0.6 + (_pulseController.value * 0.4),
                                  ),
                                  blurRadius: 80 + (_pulseController.value * 40),
                                  spreadRadius: 20 + (_pulseController.value * 15),
                                ),
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 30,
                                offset: const Offset(0, 15),
                              ),
                            ],
                            border: Border.all(
                              color: _isRecording
                                  ? AppColors.borderAccent
                                  : AppColors.borderGlass,
                              width: 2,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(90),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Center(
                                child: _isProcessing
                                    ? const CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 3,
                                      )
                                    : Icon(
                                        _isRecording ? Icons.stop_rounded : Icons.mic_none,
                                        size: 72,
                                        color: Colors.white,
                                      ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Status Card
                  GlassCard(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    borderRadius: 20,
                    child: Text(
                      _isProcessing
                          ? 'Extracting intelligence...'
                          : (_isPaused
                              ? 'Recording paused - Tap to resume'
                              : (_isRecording
                                  ? 'Listening to meeting...'
                                  : 'Tap to begin recording')),
                      style: TextStyle(
                        color: _isRecording
                            ? AppColors.primaryAccent
                            : AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  
                  // Pause Button
                  if (_isRecording && !_isProcessing) ...[
                    const SizedBox(height: 24),
                    NeumorphicButton(
                      width: 80,
                      height: 80,
                      borderRadius: 40,
                      onPressed: _togglePause,
                      child: Icon(
                        _isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                        size: 36,
                        color: _isPaused ? const Color(0xFFF59E0B) : AppColors.textPrimary,
                      ),
                    ),
                  ],
                  
                  // Upload Button
                  if (!_isRecording && !_isProcessing) ...[
                    const SizedBox(height: 24),
                    NeumorphicButton(
                      width: 200,
                      height: 52,
                      onPressed: _uploadAudioFile,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.upload_file,
                            size: 20,
                            color: AppColors.textPrimary,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Upload Audio',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
