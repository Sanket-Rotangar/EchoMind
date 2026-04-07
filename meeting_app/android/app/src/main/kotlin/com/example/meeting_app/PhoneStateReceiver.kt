package com.example.meeting_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.telephony.TelephonyManager
import android.util.Log

class PhoneStateReceiver : BroadcastReceiver() {
    
    companion object {
        private const val TAG = "PhoneStateReceiver"
        
        // Track last state to avoid duplicate events
        private var lastState: String? = null
        private var isCallRecordingEnabled: Boolean = false
        
        // Callback to notify Flutter about call state changes
        var onCallStateChanged: ((Boolean) -> Unit)? = null
        
        fun setCallRecordingEnabled(enabled: Boolean) {
            isCallRecordingEnabled = enabled
            Log.d(TAG, "Call recording enabled: $enabled")
        }
    }
    
    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "onReceive: ${intent.action}")
        
        if (!isCallRecordingEnabled) {
            Log.d(TAG, "Call recording is disabled, ignoring")
            return
        }
        
        when (intent.action) {
            TelephonyManager.ACTION_PHONE_STATE_CHANGED -> {
                val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE)
                Log.d(TAG, "Phone state changed: $state (last: $lastState)")
                
                // Avoid duplicate events
                if (state == lastState) {
                    return
                }
                lastState = state
                
                when (state) {
                    TelephonyManager.EXTRA_STATE_RINGING -> {
                        // Incoming call ringing
                        Log.d(TAG, "Incoming call ringing - notifying Flutter")
                        onCallStateChanged?.invoke(true)
                    }
                    TelephonyManager.EXTRA_STATE_OFFHOOK -> {
                        // Call answered or outgoing call started
                        Log.d(TAG, "Call active (offhook) - notifying Flutter")
                        onCallStateChanged?.invoke(true)
                    }
                    TelephonyManager.EXTRA_STATE_IDLE -> {
                        // Call ended
                        Log.d(TAG, "Call ended (idle) - notifying Flutter")
                        onCallStateChanged?.invoke(false)
                    }
                }
            }
            Intent.ACTION_NEW_OUTGOING_CALL -> {
                // Outgoing call initiated
                val phoneNumber = intent.getStringExtra(Intent.EXTRA_PHONE_NUMBER)
                Log.d(TAG, "Outgoing call to: $phoneNumber - notifying Flutter")
                onCallStateChanged?.invoke(true)
            }
        }
    }
}
