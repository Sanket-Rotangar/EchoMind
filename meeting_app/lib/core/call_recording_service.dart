import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:phone_state/phone_state.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

/// Enum representing the current call state
enum CallState {
  idle,
  ringing,
  offHook, // Active call
  unknown,
}

/// Recording mode - determines how audio is captured
enum RecordingMode {
  microphoneOnly,  // Only captures your voice (fallback)
  systemAudio,     // Captures both sides via accessibility service (Android 10+)
}

/// Service to detect phone calls and manage call recording
class CallRecordingService extends ChangeNotifier {
  static final CallRecordingService _instance = CallRecordingService._internal();
  factory CallRecordingService() => _instance;
  CallRecordingService._internal();

  // Method channel for native Android communication
  static const MethodChannel _channel = MethodChannel('com.echomind/call_recording');

  // Preferences keys
  static const String _prefKeyEnabled = 'call_recording_enabled';
  static const String _prefKeyRecordingMode = 'call_recording_mode';

  // State
  bool _isEnabled = false;
  bool _isInitialized = false;
  CallState _callState = CallState.idle;
  bool _isRecording = false;
  bool _isProcessing = false;
  bool _showOverlay = false;
  String? _currentRecordingPath;
  DateTime? _recordingStartTime;
  StreamSubscription<PhoneState>? _phoneStateSubscription;
  final AudioRecorder _audioRecorder = AudioRecorder();
  Timer? _recordingTimer;
  
  // Recording mode
  RecordingMode _recordingMode = RecordingMode.microphoneOnly;
  bool _isAccessibilityEnabled = false;
  bool _isAndroid10OrHigher = false;

  // Getters
  bool get isEnabled => _isEnabled;
  bool get isInitialized => _isInitialized;
  CallState get callState => _callState;
  bool get isRecording => _isRecording;
  bool get isProcessing => _isProcessing;
  bool get showOverlay => _showOverlay;
  bool get isInCall => _callState == CallState.offHook || _callState == CallState.ringing;
  RecordingMode get recordingMode => _recordingMode;
  bool get isAccessibilityEnabled => _isAccessibilityEnabled;
  bool get isAndroid10OrHigher => _isAndroid10OrHigher;
  bool get canCaptureSystemAudio => _isAndroid10OrHigher && _isAccessibilityEnabled;
  
  Duration get recordingDuration {
    if (_recordingStartTime == null) return Duration.zero;
    return DateTime.now().difference(_recordingStartTime!);
  }

  /// Initialize the service and restore saved settings
  Future<void> init() async {
    if (_isInitialized) return;

    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool(_prefKeyEnabled) ?? false;
    
    // Load recording mode preference
    final modeIndex = prefs.getInt(_prefKeyRecordingMode) ?? 0;
    _recordingMode = RecordingMode.values[modeIndex];
    
    _isInitialized = true;

    // Set up method channel handler for native -> Flutter calls
    _channel.setMethodCallHandler(_handleNativeMethodCall);

    // Check Android version and accessibility service status
    if (Platform.isAndroid) {
      await _checkAndroidCapabilities();
      
      // Notify native side of current state
      if (_isEnabled) {
        try {
          await _channel.invokeMethod('setCallRecordingEnabled', {'enabled': true});
          debugPrint('Native side notified on init: call recording enabled');
        } catch (e) {
          debugPrint('Error notifying native side on init: $e');
        }
      }
    }

    if (_isEnabled) {
      await _startPhoneStateListener();
    }

    notifyListeners();
  }

  /// Handle method calls from native code (Android)
  Future<dynamic> _handleNativeMethodCall(MethodCall call) async {
    debugPrint('Native method call: ${call.method}');
    
    switch (call.method) {
      case 'callStarted':
        debugPrint('Native: call started');
        _callState = CallState.offHook;
        _showOverlay = true;
        notifyListeners();
        return true;
        
      case 'callEnded':
        debugPrint('Native: call ended');
        _callState = CallState.idle;
        _showOverlay = false;
        
        // Stop recording if active
        if (_isRecording) {
          debugPrint('Stopping recording because call ended');
          await stopRecording();
        }
        notifyListeners();
        return true;
      
      case 'toggleRecording':
        final shouldStart = call.arguments?['start'] as bool? ?? false;
        debugPrint('Native: toggle recording, shouldStart=$shouldStart');
        if (shouldStart && !_isRecording) {
          await startRecording();
        } else if (!shouldStart && _isRecording) {
          await stopRecording();
        } else {
          await toggleRecording();
        }
        return true;
      
      case 'overlayClosed':
        debugPrint('Native: overlay closed by user');
        _showOverlay = false;
        notifyListeners();
        return true;
        
      // Legacy handlers for compatibility
      case 'showCallOverlay':
        debugPrint('Native requested: show overlay (legacy)');
        if (!_isEnabled) {
          debugPrint('Call recording not enabled, ignoring');
          return false;
        }
        _callState = CallState.offHook;
        _showOverlay = true;
        notifyListeners();
        return true;
        
      case 'hideCallOverlay':
        debugPrint('Native requested: hide overlay (legacy)');
        _callState = CallState.idle;
        _showOverlay = false;
        if (_isRecording) {
          await stopRecording();
        }
        notifyListeners();
        return true;
        
      default:
        debugPrint('Unknown native method: ${call.method}');
        return null;
    }
  }

  /// Check Android-specific capabilities
  Future<void> _checkAndroidCapabilities() async {
    try {
      _isAndroid10OrHigher = await _channel.invokeMethod('isAndroid10OrHigher') ?? false;
      _isAccessibilityEnabled = await _channel.invokeMethod('isAccessibilityEnabled') ?? false;
      
      debugPrint('Android 10+: $_isAndroid10OrHigher, Accessibility: $_isAccessibilityEnabled');
    } catch (e) {
      debugPrint('Error checking Android capabilities: $e');
    }
  }

  /// Refresh accessibility service status
  Future<void> refreshAccessibilityStatus() async {
    if (Platform.isAndroid) {
      try {
        _isAccessibilityEnabled = await _channel.invokeMethod('isAccessibilityEnabled') ?? false;
        notifyListeners();
      } catch (e) {
        debugPrint('Error refreshing accessibility status: $e');
      }
    }
  }

  /// Open accessibility settings for user to enable the service
  Future<void> openAccessibilitySettings() async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('openAccessibilitySettings');
      } catch (e) {
        debugPrint('Error opening accessibility settings: $e');
      }
    }
  }

  /// Set the recording mode
  Future<void> setRecordingMode(RecordingMode mode) async {
    if (_recordingMode == mode) return;
    
    _recordingMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKeyRecordingMode, mode.index);
    
    notifyListeners();
  }

  /// Enable or disable call recording feature
  Future<void> setEnabled(bool enabled) async {
    if (_isEnabled == enabled) return;

    _isEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyEnabled, enabled);

    if (enabled) {
      final hasPermissions = await _requestPermissions();
      if (!hasPermissions) {
        _isEnabled = false;
        await prefs.setBool(_prefKeyEnabled, false);
        notifyListeners();
        return;
      }
      await _startPhoneStateListener();
      
      // Notify native side to register broadcast receiver
      if (Platform.isAndroid) {
        try {
          await _channel.invokeMethod('setCallRecordingEnabled', {'enabled': true});
          debugPrint('Native side notified: call recording enabled');
        } catch (e) {
          debugPrint('Error notifying native side: $e');
        }
      }
    } else {
      await _stopPhoneStateListener();
      
      // Notify native side to unregister broadcast receiver and hide overlay
      if (Platform.isAndroid) {
        try {
          await _channel.invokeMethod('setCallRecordingEnabled', {'enabled': false});
          debugPrint('Native side notified: call recording disabled');
        } catch (e) {
          debugPrint('Error notifying native side: $e');
        }
      }
    }

    notifyListeners();
  }

  /// Request all required permissions
  Future<bool> _requestPermissions() async {
    // Request phone permission
    final phoneStatus = await Permission.phone.request();
    if (!phoneStatus.isGranted) {
      debugPrint('Phone permission denied');
      return false;
    }

    // Request microphone permission
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      debugPrint('Microphone permission denied');
      return false;
    }

    // Check if overlay permission is granted (using native check)
    if (Platform.isAndroid) {
      try {
        final hasOverlayPermission = await _channel.invokeMethod('canDrawOverlays') ?? false;
        debugPrint('Overlay permission check: $hasOverlayPermission');
        
        if (!hasOverlayPermission) {
          // Open system settings to grant overlay permission
          await Permission.systemAlertWindow.request();
          
          // Wait a bit for user to potentially grant permission quickly
          await Future.delayed(const Duration(milliseconds: 500));
          
          // Re-check permission
          final nowGranted = await _channel.invokeMethod('canDrawOverlays') ?? false;
          debugPrint('Overlay permission after request: $nowGranted');
          
          if (!nowGranted) {
            debugPrint('Overlay permission not yet granted - user needs to enable in settings');
            return false;
          }
        }
      } catch (e) {
        debugPrint('Error checking overlay permission: $e');
      }
    }

    return true;
  }
  
  /// Check and refresh all permissions status (call when app resumes)
  Future<bool> checkPermissions() async {
    final phoneGranted = await Permission.phone.isGranted;
    final micGranted = await Permission.microphone.isGranted;
    
    bool overlayGranted = true;
    if (Platform.isAndroid) {
      try {
        overlayGranted = await _channel.invokeMethod('canDrawOverlays') ?? false;
      } catch (e) {
        debugPrint('Error checking overlay permission: $e');
      }
    }
    
    debugPrint('Permission check - Phone: $phoneGranted, Mic: $micGranted, Overlay: $overlayGranted');
    
    return phoneGranted && micGranted && overlayGranted;
  }
  
  /// Re-check permissions and update enabled state if permissions are now granted
  Future<void> refreshPermissionsAndEnable() async {
    final allGranted = await checkPermissions();
    debugPrint('All permissions granted: $allGranted');
    
    if (allGranted && !_isEnabled) {
      // User has granted all permissions, now we can enable
      _isEnabled = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKeyEnabled, true);
      await _startPhoneStateListener();
      
      // Notify native side
      if (Platform.isAndroid) {
        try {
          await _channel.invokeMethod('setCallRecordingEnabled', {'enabled': true});
        } catch (e) {
          debugPrint('Error notifying native side: $e');
        }
      }
      
      notifyListeners();
    } else if (!allGranted && _isEnabled) {
      // Permissions were revoked
      _isEnabled = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKeyEnabled, false);
      await _stopPhoneStateListener();
      notifyListeners();
    }
  }

  /// Start listening to phone state changes
  Future<void> _startPhoneStateListener() async {
    await _stopPhoneStateListener();

    // Set up phone state listener
    _phoneStateSubscription = PhoneState.stream.listen((PhoneState state) {
      _handlePhoneStateChange(state);
    });

    debugPrint('Phone state listener started');
  }

  /// Stop listening to phone state changes
  Future<void> _stopPhoneStateListener() async {
    await _phoneStateSubscription?.cancel();
    _phoneStateSubscription = null;
    debugPrint('Phone state listener stopped');
  }

  /// Handle phone state changes
  void _handlePhoneStateChange(PhoneState state) {
    CallState newState;

    switch (state.status) {
      case PhoneStateStatus.CALL_INCOMING:
        newState = CallState.ringing;
        break;
      case PhoneStateStatus.CALL_STARTED:
        newState = CallState.offHook;
        break;
      case PhoneStateStatus.CALL_ENDED:
        newState = CallState.idle;
        break;
      case PhoneStateStatus.NOTHING:
      default:
        newState = CallState.idle;
        break;
    }

    if (newState != _callState) {
      _callState = newState;
      _onCallStateChanged();
    }
  }

  /// Called when call state changes
  void _onCallStateChanged() {
    debugPrint('Call state changed: $_callState');

    if (_callState == CallState.ringing || _callState == CallState.offHook) {
      // Call started or ringing - native side shows overlay via BroadcastReceiver
      _showOverlay = true;
    } else if (_callState == CallState.idle) {
      // Call ended - if recording was active, stop and process
      if (_isRecording) {
        stopRecording();
      }
      _showOverlay = false;
    }

    notifyListeners();
  }

  /// Start recording the call
  /// For phone calls, we always use native Android recording as it handles
  /// audio routing during calls better than Flutter's record package
  Future<bool> startRecording() async {
    if (_isRecording || _isProcessing) return false;

    try {
      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      
      debugPrint('Starting call recording...');
      debugPrint('Recording mode: $_recordingMode');
      debugPrint('Android 10+: $_isAndroid10OrHigher');
      debugPrint('Is Android: ${Platform.isAndroid}');
      
      if (Platform.isAndroid) {
        // Always use native Android recording for phone calls
        // This handles audio routing during calls much better
        _currentRecordingPath = '${dir.path}/call_recording_$timestamp.pcm';
        
        debugPrint('Using native Android recording: $_currentRecordingPath');
        
        final success = await _channel.invokeMethod('startSystemAudioRecording', {
          'outputPath': _currentRecordingPath,
        });
        
        if (success != true) {
          debugPrint('Native recording failed, trying Flutter recorder...');
          return await _startMicrophoneRecording(dir, timestamp);
        }
        
        debugPrint('Native recording started successfully');
        
        _isRecording = true;
        _recordingStartTime = DateTime.now();
        
        // Start timer to update native overlay
        _startRecordingTimer();

        // Update native overlay
        _updateNativeOverlay();

        notifyListeners();
        return true;
      } else {
        // iOS or other platforms - use Flutter's record package
        return await _startMicrophoneRecording(dir, timestamp);
      }
    } catch (e, stackTrace) {
      debugPrint('Error starting recording: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  }

  /// Start microphone-only recording (fallback method)
  Future<bool> _startMicrophoneRecording(Directory dir, int timestamp) async {
    try {
      // Check microphone permission
      if (!await _audioRecorder.hasPermission()) {
        debugPrint('No microphone permission for recording');
        return false;
      }

      _currentRecordingPath = '${dir.path}/call_recording_$timestamp.m4a';

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: _currentRecordingPath!,
      );

      _isRecording = true;
      _recordingStartTime = DateTime.now();

      // Start timer to update native overlay
      _startRecordingTimer();
      
      // Update native overlay
      _updateNativeOverlay();

      notifyListeners();
      debugPrint('Microphone recording started: $_currentRecordingPath');
      return true;
    } catch (e) {
      debugPrint('Error starting microphone recording: $e');
      return false;
    }
  }
  
  void _startRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateNativeOverlay();
    });
  }
  
  void _stopRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
  }
  
  void _updateNativeOverlay() {
    if (Platform.isAndroid) {
      try {
        final seconds = recordingDuration.inSeconds;
        _channel.invokeMethod('updateOverlayRecording', {
          'recording': _isRecording,
          'seconds': seconds,
        });
      } catch (e) {
        debugPrint('Error updating native overlay: $e');
      }
    }
  }

  /// Stop recording and process the audio
  Future<void> stopRecording() async {
    if (!_isRecording) {
      debugPrint('stopRecording called but not recording');
      return;
    }

    _stopRecordingTimer();
    debugPrint('Stopping recording...');

    try {
      String? filePath;
      
      debugPrint('Current recording path: $_currentRecordingPath');
      
      // Check if we're using native Android recording (PCM file)
      final isNativeRecording = Platform.isAndroid && 
                                _currentRecordingPath?.endsWith('.pcm') == true;
      
      debugPrint('Is native recording: $isNativeRecording');
      
      if (isNativeRecording) {
        // Stop native Android recording (returns WAV path)
        debugPrint('Stopping native Android recording...');
        filePath = await _channel.invokeMethod('stopSystemAudioRecording');
        debugPrint('Native recording stopped, filePath: $filePath');
      } else {
        // Stop Flutter recorder (m4a file)
        debugPrint('Stopping Flutter recorder...');
        filePath = await _audioRecorder.stop();
        debugPrint('Flutter recorder stopped, filePath: $filePath');
      }
      
      _isRecording = false;
      _recordingStartTime = null;

      // Update native overlay
      _updateNativeOverlay();

      if (filePath != null && filePath.isNotEmpty) {
        // Check if file exists and has content
        final file = File(filePath);
        if (await file.exists()) {
          final fileSize = await file.length();
          debugPrint('Recording file exists, size: $fileSize bytes');
          
          if (fileSize > 1000) { // At least 1KB
            _isProcessing = true;
            notifyListeners();

            // Process the recording
            await _processRecording(filePath);
          } else {
            debugPrint('Recording file too small ($fileSize bytes), skipping processing');
          }
        } else {
          debugPrint('Recording file does not exist: $filePath');
        }
      } else {
        debugPrint('No file path returned from recording stop');
      }

      _isProcessing = false;
      notifyListeners();
      debugPrint('Call recording stopped successfully');
    } catch (e, stackTrace) {
      debugPrint('Error stopping recording: $e');
      debugPrint('Stack trace: $stackTrace');
      _isRecording = false;
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Process the recorded audio file
  Future<void> _processRecording(String filePath) async {
    try {
      debugPrint('Processing call recording: $filePath');
      
      final result = await ApiService.processMeetingAudio(filePath);
      
      if (result['success'] == true) {
        debugPrint('Call recording processed successfully, meetingId: ${result['meetingId']}');
      } else {
        debugPrint('Call recording processing failed: $result');
      }
    } catch (e, stackTrace) {
      debugPrint('Error processing recording: $e');
      debugPrint('Processing stack trace: $stackTrace');
    }
  }

  /// Toggle recording state
  Future<void> toggleRecording() async {
    if (_isRecording) {
      await stopRecording();
    } else {
      await startRecording();
    }
  }

  /// Clean up resources
  @override
  void dispose() {
    _stopPhoneStateListener();
    _stopRecordingTimer();
    _audioRecorder.dispose();
    super.dispose();
  }
}
