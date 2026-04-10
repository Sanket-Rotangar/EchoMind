import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../domain/services/audio_recording_service.dart';

final class AudioRecordingServiceImpl implements AudioRecordingService {
  AudioRecordingServiceImpl() : _record = AudioRecorder();

  final AudioRecorder _record;

  @override
  Future<String> start() async {
    final hasPermission = await _record.hasPermission();
    if (!hasPermission) {
      throw StateError('Microphone permission is not granted');
    }

    final outputPath = await _buildOutputPath();
    const config = RecordConfig(
      encoder: AudioEncoder.aacLc,
      bitRate: 128000,
      sampleRate: 44100,
    );

    await _record.start(config, path: outputPath);
    return outputPath;
  }

  @override
  Future<String?> stop() {
    return _record.stop();
  }

  @override
  Future<bool> isRecording() {
    return _record.isRecording();
  }

  @override
  Future<void> dispose() {
    return _record.dispose();
  }

  Future<String> _buildOutputPath() async {
    final docsDirectory = await getApplicationDocumentsDirectory();
    final recordingsDir = Directory('${docsDirectory.path}/recordings');
    if (!await recordingsDir.exists()) {
      await recordingsDir.create(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${recordingsDir.path}/meeting_$timestamp.m4a';
  }
}
