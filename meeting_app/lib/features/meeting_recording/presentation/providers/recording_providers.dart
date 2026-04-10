import 'dart:async';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/services/background/foreground_recording_task_handler.dart';
import '../../../../core/services/notification_service.dart';
import '../../application/recording_state.dart';
import '../../data/services/audio_recording_service_impl.dart';
import '../../domain/services/audio_recording_service.dart';
import '../../models/recording_status.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService.instance;
});

final audioRecordingServiceProvider = Provider<AudioRecordingService>((ref) {
  final service = AudioRecordingServiceImpl();
  ref.onDispose(service.dispose);
  return service;
});

final recordingControllerProvider =
    StateNotifierProvider<RecordingController, RecordingState>((ref) {
      final controller = RecordingController(
        audioService: ref.watch(audioRecordingServiceProvider),
        notificationService: ref.watch(notificationServiceProvider),
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

class RecordingController extends StateNotifier<RecordingState> {
  RecordingController({
    required AudioRecordingService audioService,
    required NotificationService notificationService,
  }) : _audioService = audioService,
       _notificationService = notificationService,
       super(RecordingState.initial) {
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
  }

  final AudioRecordingService _audioService;
  final NotificationService _notificationService;
  DateTime? _recordingStartedAt;

  Future<bool> requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<void> startRecording() async {
    if (state.isRecording || state.status == RecordingStatus.processing) {
      return;
    }

    state = state.copyWith(
      status: RecordingStatus.processing,
      clearError: true,
    );

    try {
      final micGranted = await requestMicrophonePermission();
      if (!micGranted) {
        throw StateError('Microphone permission denied');
      }

      await _notificationService.requestPermissionIfNeeded();

      final outputPath = await _audioService.start();
      _recordingStartedAt = DateTime.now();

      await _startOrUpdateForegroundService();
      FlutterForegroundTask.sendDataToTask({
        'action': 'sync_start',
        'startedAtMillis': _recordingStartedAt!.millisecondsSinceEpoch,
      });

      state = RecordingState(
        status: RecordingStatus.recording,
        duration: Duration.zero,
        currentFilePath: outputPath,
      );
    } catch (error) {
      state = state.copyWith(
        status: RecordingStatus.error,
        errorMessage: error.toString(),
      );
    }
  }

  Future<void> stopRecording() async {
    if (!state.isRecording && state.status != RecordingStatus.error) {
      return;
    }

    state = state.copyWith(
      status: RecordingStatus.processing,
      clearError: true,
    );

    try {
      final outputPath = await _audioService.stop();
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }

      state = RecordingState(
        status: RecordingStatus.idle,
        duration: state.duration,
        currentFilePath: outputPath ?? state.currentFilePath,
      );
    } catch (error) {
      state = state.copyWith(
        status: RecordingStatus.error,
        errorMessage: error.toString(),
      );
    }
  }

  Future<void> _startOrUpdateForegroundService() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: NotificationService.foregroundChannelId,
        channelName: NotificationService.foregroundChannelName,
        channelDescription: NotificationService.foregroundChannelDescription,
        onlyAlertOnce: true,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(1000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: NotificationService.recordingTitle,
        notificationText: 'Recording 00:00:00',
      );
      return;
    }

    await FlutterForegroundTask.startService(
      notificationTitle: NotificationService.recordingTitle,
      notificationText: 'Recording 00:00:00',
      notificationButtons: const [
        NotificationButton(
          id: NotificationService.stopActionId,
          text: 'Stop Recording / End Meeting',
        ),
      ],
      callback: recordingTaskStartCallback,
    );
  }

  void _onTaskData(Object message) {
    if (message is! Map) {
      return;
    }

    final type = message['type'];

    if (type == 'duration') {
      final seconds = message['seconds'];
      if (seconds is int && state.isRecording) {
        state = state.copyWith(duration: Duration(seconds: seconds));
      }
      return;
    }

    if (type == 'notification_stop') {
      unawaited(stopRecording());
    }
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    super.dispose();
  }
}
