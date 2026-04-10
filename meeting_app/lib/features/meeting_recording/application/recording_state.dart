import '../models/recording_status.dart';

class RecordingState {
  const RecordingState({
    required this.status,
    required this.duration,
    this.currentFilePath,
    this.errorMessage,
  });

  final RecordingStatus status;
  final Duration duration;
  final String? currentFilePath;
  final String? errorMessage;

  bool get isRecording => status == RecordingStatus.recording;

  RecordingState copyWith({
    RecordingStatus? status,
    Duration? duration,
    String? currentFilePath,
    String? errorMessage,
    bool clearError = false,
  }) {
    return RecordingState(
      status: status ?? this.status,
      duration: duration ?? this.duration,
      currentFilePath: currentFilePath ?? this.currentFilePath,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  static const initial = RecordingState(
    status: RecordingStatus.idle,
    duration: Duration.zero,
  );
}
