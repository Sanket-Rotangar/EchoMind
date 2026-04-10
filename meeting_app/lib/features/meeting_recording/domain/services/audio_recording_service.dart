abstract interface class AudioRecordingService {
  Future<String> start();

  Future<String?> stop();

  Future<bool> isRecording();

  Future<void> dispose();
}
