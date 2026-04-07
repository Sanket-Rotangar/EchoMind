package com.example.meeting_app

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.telephony.TelephonyManager
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.echomind/call_recording"
    private val TAG = "MainActivity"
    
    private var methodChannel: MethodChannel? = null
    // COMMENTED OUT - Call recording feature disabled due to Android limitations
    // private var phoneStateReceiver: PhoneStateReceiver? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        
        // COMMENTED OUT - Call recording feature disabled due to Android limitations
        /*
        // Set up callbacks for native overlay
        CallOverlayService.onRecordingToggle = { shouldRecord ->
            Log.d(TAG, "Recording toggle from native overlay: $shouldRecord")
            mainHandler.post {
                methodChannel?.invokeMethod("toggleRecording", mapOf("start" to shouldRecord))
            }
        }
        
        CallOverlayService.onOverlayClosed = {
            Log.d(TAG, "Overlay closed by user")
            mainHandler.post {
                methodChannel?.invokeMethod("overlayClosed", null)
            }
        }
        */
        
        methodChannel?.setMethodCallHandler { call, result ->
            // COMMENTED OUT - Call recording feature disabled due to Android limitations
            // All method calls return not implemented since the feature is disabled
            result.notImplemented()
            
            /*
            when (call.method) {
                "isAccessibilityEnabled" -> {
                    val isEnabled = CallAudioCaptureService.isAccessibilityServiceEnabled(this)
                    result.success(isEnabled)
                }
                
                "openAccessibilitySettings" -> {
                    CallAudioCaptureService.openAccessibilitySettings(this)
                    result.success(true)
                }
                
                "isAndroid10OrHigher" -> {
                    result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                }
                
                "startSystemAudioRecording" -> {
                    val outputPath = call.argument<String>("outputPath")
                    if (outputPath != null) {
                        val success = CallAudioCaptureService.startRecording(this, outputPath)
                        result.success(success)
                    } else {
                        result.error("INVALID_ARGUMENT", "outputPath is required", null)
                    }
                }
                
                "stopSystemAudioRecording" -> {
                    val filePath = CallAudioCaptureService.stopRecording()
                    result.success(filePath)
                }
                
                "isRecording" -> {
                    result.success(CallAudioCaptureService.isRecording)
                }
                
                "setCallRecordingEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    PhoneStateReceiver.setCallRecordingEnabled(enabled)
                    
                    if (enabled) {
                        registerPhoneStateReceiver()
                    } else {
                        unregisterPhoneStateReceiver()
                        // Also hide overlay if visible
                        CallOverlayService.hideOverlay(this)
                    }
                    
                    result.success(true)
                }
                
                "showNativeOverlay" -> {
                    val success = CallOverlayService.showOverlay(this)
                    result.success(success)
                }
                
                "hideNativeOverlay" -> {
                    CallOverlayService.hideOverlay(this)
                    result.success(true)
                }
                
                "updateOverlayRecording" -> {
                    val recording = call.argument<Boolean>("recording") ?: false
                    val seconds = call.argument<Int>("seconds") ?: 0
                    CallOverlayService.updateRecordingState(recording, seconds)
                    result.success(true)
                }
                
                "canDrawOverlays" -> {
                    result.success(Settings.canDrawOverlays(this))
                }
                
                else -> {
                    result.notImplemented()
                }
            }
            */
        }
    }
    
    // COMMENTED OUT - Call recording feature disabled due to Android limitations
    /*
    private fun registerPhoneStateReceiver() {
        if (phoneStateReceiver == null) {
            phoneStateReceiver = PhoneStateReceiver()
            
            // Set up callback to notify Flutter AND show native overlay
            PhoneStateReceiver.onCallStateChanged = { isInCall ->
                Log.d(TAG, "Call state callback: isInCall=$isInCall")
                
                if (isInCall) {
                    // Show native overlay directly (doesn't require foreground service)
                    CallOverlayService.showOverlay(this)
                } else {
                    // Hide overlay
                    CallOverlayService.hideOverlay(this)
                }
                
                // Also notify Flutter
                mainHandler.post {
                    if (isInCall) {
                        methodChannel?.invokeMethod("callStarted", null)
                    } else {
                        methodChannel?.invokeMethod("callEnded", null)
                    }
                }
            }
            
            val filter = IntentFilter().apply {
                addAction(TelephonyManager.ACTION_PHONE_STATE_CHANGED)
                addAction(Intent.ACTION_NEW_OUTGOING_CALL)
            }
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(phoneStateReceiver, filter, Context.RECEIVER_EXPORTED)
            } else {
                registerReceiver(phoneStateReceiver, filter)
            }
            Log.d(TAG, "PhoneStateReceiver registered")
        }
    }
    
    private fun unregisterPhoneStateReceiver() {
        phoneStateReceiver?.let {
            try {
                PhoneStateReceiver.onCallStateChanged = null
                unregisterReceiver(it)
                Log.d(TAG, "PhoneStateReceiver unregistered")
            } catch (e: Exception) {
                Log.e(TAG, "Error unregistering receiver: ${e.message}")
            }
            phoneStateReceiver = null
        }
    }
    */
    
    override fun onDestroy() {
        // COMMENTED OUT - Call recording feature disabled due to Android limitations
        // CallOverlayService.onRecordingToggle = null
        // CallOverlayService.onOverlayClosed = null
        // unregisterPhoneStateReceiver()
        super.onDestroy()
    }
}
