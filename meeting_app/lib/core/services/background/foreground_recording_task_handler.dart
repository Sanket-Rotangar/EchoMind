import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../notification_service.dart';

class ForegroundRecordingTaskHandler extends TaskHandler {
  DateTime? _recordingStartedAt;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter taskStarter) async {
    _recordingStartedAt = timestamp;
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    final startedAt = _recordingStartedAt ?? timestamp;
    final duration = timestamp.difference(startedAt);

    FlutterForegroundTask.updateService(
      notificationTitle: NotificationService.recordingTitle,
      notificationText:
          'Recording ${NotificationService.durationLabel(duration)}',
    );

    FlutterForegroundTask.sendDataToMain({
      'type': 'duration',
      'seconds': duration.inSeconds,
    });
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  @override
  void onReceiveData(Object data) {
    if (data is! Map) {
      return;
    }

    final action = data['action'];

    if (action == 'sync_start') {
      final epochMillis = data['startedAtMillis'];
      if (epochMillis is int) {
        _recordingStartedAt = DateTime.fromMillisecondsSinceEpoch(epochMillis);
      }
      return;
    }

    if (action == 'stop') {
      FlutterForegroundTask.stopService();
    }
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id != NotificationService.stopActionId) {
      return;
    }

    FlutterForegroundTask.sendDataToMain({'type': 'notification_stop'});
    FlutterForegroundTask.stopService();
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }

  @override
  void onNotificationDismissed() {}
}

@pragma('vm:entry-point')
void recordingTaskStartCallback() {
  FlutterForegroundTask.setTaskHandler(ForegroundRecordingTaskHandler());
}
