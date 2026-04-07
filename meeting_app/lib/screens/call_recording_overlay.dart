import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

class CallRecordingOverlayApp extends StatelessWidget {
  const CallRecordingOverlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const CallRecordingOverlay(),
    );
  }
}

class CallRecordingOverlay extends StatefulWidget {
  const CallRecordingOverlay({super.key});

  @override
  State<CallRecordingOverlay> createState() => _CallRecordingOverlayState();
}

class _CallRecordingOverlayState extends State<CallRecordingOverlay> {
  bool _isRecording = false;
  bool _isProcessing = false;
  Timer? _recordingTimer;
  int _recordingSeconds = 0;
  StreamSubscription? _dataSubscription;

  @override
  void initState() {
    super.initState();

    // Listen for data from main app
    _dataSubscription = FlutterOverlayWindow.overlayListener.listen((data) {
      if (data is Map) {
        setState(() {
          if (data.containsKey('recording')) {
            _isRecording = data['recording'] == true;
            if (_isRecording) {
              _startTimer();
            } else {
              _stopTimer();
            }
          }
          if (data.containsKey('processing')) {
            _isProcessing = data['processing'] == true;
          }
          if (data.containsKey('close')) {
            // Close the overlay
            FlutterOverlayWindow.closeOverlay();
          }
        });
      }
    });
  }

  void _startTimer() {
    _recordingTimer?.cancel();
    _recordingSeconds = 0;
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _recordingSeconds++;
      });
    });
  }

  void _stopTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _dataSubscription?.cancel();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  Future<void> _toggleRecording() async {
    if (_isProcessing) return;
    
    // Send message to main app to toggle recording
    await FlutterOverlayWindow.shareData({
      'action': _isRecording ? 'stop_recording' : 'start_recording'
    });
  }

  Future<void> _closeOverlay() async {
    await FlutterOverlayWindow.closeOverlay();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: _toggleRecording,
        child: Container(
          width: 140,
          height: 56,
          decoration: BoxDecoration(
            color: _isRecording 
                ? const Color(0xFFFF6B6B) 
                : const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: _isRecording 
                  ? const Color(0xFFFF6B6B) 
                  : const Color(0xFFFFB07C),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(128),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Recording indicator
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isRecording 
                      ? Colors.white 
                      : const Color(0xFFFF6B6B),
                ),
                child: _isRecording 
                    ? const Icon(Icons.stop, size: 12, color: Color(0xFFFF6B6B))
                    : null,
              ),
              const SizedBox(width: 8),
              // Text
              Text(
                _isRecording 
                    ? _formatDuration(_recordingSeconds)
                    : 'Record',
                style: TextStyle(
                  color: _isRecording ? Colors.white : const Color(0xFFFFB07C),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              // Close button
              if (!_isRecording) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _closeOverlay,
                  child: const Icon(
                    Icons.close,
                    size: 16,
                    color: Colors.white54,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
