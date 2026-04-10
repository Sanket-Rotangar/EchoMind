import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const String foregroundChannelId = 'echomind_recording_channel';
  static const String foregroundChannelName = 'EchoMind Recording';
  static const String foregroundChannelDescription =
      'Persistent recording status and controls';

  static const String stopActionId = 'stop_recording';
  static const String recordingTitle = 'EchoMind Recording';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initSettings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(initSettings);

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidPlugin != null) {
      const channel = AndroidNotificationChannel(
        foregroundChannelId,
        foregroundChannelName,
        description: foregroundChannelDescription,
        importance: Importance.low,
      );
      await androidPlugin.createNotificationChannel(channel);
    }
  }

  Future<bool> requestPermissionIfNeeded() async {
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidPlugin == null) {
      return true;
    }

    final granted = await androidPlugin.areNotificationsEnabled();
    if (granted == true) {
      return true;
    }

    return await androidPlugin.requestNotificationsPermission() ?? false;
  }

  Future<void> showMeetingSummaryReady({
    required String title,
    required String body,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'echomind_general',
        'EchoMind Updates',
        channelDescription: 'General updates for meetings',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    await _plugin.show(
      9001,
      title,
      body,
      details,
      payload: 'meeting_summary_ready',
    );
  }

  static String durationLabel(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @visibleForTesting
  FlutterLocalNotificationsPlugin get plugin => _plugin;
}
