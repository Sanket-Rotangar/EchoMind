package com.example.meeting_app

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Accessibility Service for capturing audio during phone calls.
 * This service attempts to capture both sides of a phone conversation on Android 10+.
 * 
 * NOTE: True call recording (both sides) requires either:
 * - Root access, OR
 * - CAPTURE_AUDIO_OUTPUT permission (system apps only), OR
 * - Device-specific OEM APIs
 * 
 * This implementation uses VOICE_COMMUNICATION which can capture:
 * - Your voice (always works)
 * - Sometimes the other party when on speaker/bluetooth (device-specific)
 */
class CallAudioCaptureService : AccessibilityService() {

    companion object {
        private const val TAG = "CallAudioCapture"
        
        // Service state
        var isServiceEnabled = false
            private set
        
        var isRecording = false
            private set
        
        private var instance: CallAudioCaptureService? = null
        
        // Audio configuration - optimized for voice
        private const val SAMPLE_RATE = 16000 // Better for speech
        private const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
        private const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
        
        // Recording state
        private var audioRecord: AudioRecord? = null
        private var recordingThread: Thread? = null
        private var outputFile: File? = null
        
        /**
         * Check if the accessibility service is enabled
         */
        fun isAccessibilityServiceEnabled(context: Context): Boolean {
            val enabledServices = android.provider.Settings.Secure.getString(
                context.contentResolver,
                android.provider.Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: return false
            
            val serviceName = "${context.packageName}/${CallAudioCaptureService::class.java.canonicalName}"
            return enabledServices.contains(serviceName)
        }
        
        /**
         * Open accessibility settings for user to enable the service
         */
        fun openAccessibilitySettings(context: Context) {
            val intent = Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS)
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            context.startActivity(intent)
        }
        
        /**
         * Start recording audio during a call
         * Uses multiple audio sources to try to capture audio
         * 
         * IMPORTANT: On most Android devices, recording phone calls requires:
         * - Putting the call on SPEAKER or using BLUETOOTH
         * - This allows the microphone to pick up both parties
         */
        fun startRecording(context: Context, outputPath: String): Boolean {
            Log.i(TAG, "=== startRecording called ===")
            Log.i(TAG, "Output path: $outputPath")
            Log.i(TAG, "isRecording: $isRecording")
            
            if (isRecording) {
                Log.w(TAG, "Already recording - returning false")
                return false
            }
            
            try {
                outputFile = File(outputPath)
                Log.i(TAG, "Output file created: ${outputFile?.absolutePath}")
                
                // Ensure parent directory exists
                outputFile?.parentFile?.mkdirs()
                
                val bufferSize = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT)
                Log.i(TAG, "Buffer size calculated: $bufferSize")
                
                if (bufferSize <= 0) {
                    Log.e(TAG, "Invalid buffer size: $bufferSize - audio format not supported")
                    return false
                }
                
                // Try different audio sources in order of preference
                // VOICE_CALL (4) - Specifically for call audio (requires system permission, but worth trying)
                // VOICE_DOWNLINK (3) - Captures incoming call audio (system permission)
                // VOICE_UPLINK (2) - Captures outgoing call audio (system permission)
                // VOICE_COMMUNICATION (7) - Best for VoIP/call scenarios
                // MIC (1) - Standard microphone
                // CAMCORDER (5) often works better for call recording on some devices
                // VOICE_RECOGNITION (6) is optimized for speech
                val audioSourcesToTry = listOf(
                    MediaRecorder.AudioSource.VOICE_CALL,             // Call audio (4) - try first, may work on some OEMs
                    MediaRecorder.AudioSource.VOICE_DOWNLINK,         // Incoming audio (3)
                    MediaRecorder.AudioSource.VOICE_UPLINK,           // Outgoing audio (2)
                    MediaRecorder.AudioSource.VOICE_COMMUNICATION,    // VoIP-style (7)
                    MediaRecorder.AudioSource.MIC,                    // Standard mic (1)
                    MediaRecorder.AudioSource.CAMCORDER,              // Camcorder mic (5)
                    MediaRecorder.AudioSource.VOICE_RECOGNITION,      // Voice recognition (6)
                    MediaRecorder.AudioSource.DEFAULT                 // System default (0)
                )
                
                Log.i(TAG, "Attempting to initialize AudioRecord with ${audioSourcesToTry.size} sources")
                
                var recordInitialized = false
                var usedSource = -1
                for (source in audioSourcesToTry) {
                    try {
                        Log.i(TAG, "Trying audio source: $source (${getSourceName(source)})")
                        audioRecord = AudioRecord(
                            source,
                            SAMPLE_RATE,
                            CHANNEL_CONFIG,
                            AUDIO_FORMAT,
                            bufferSize * 4 // Larger buffer for stability
                        )
                        
                        val state = audioRecord?.state
                        Log.i(TAG, "Audio source $source: state=$state (expected: ${AudioRecord.STATE_INITIALIZED})")
                        
                        if (state == AudioRecord.STATE_INITIALIZED) {
                            Log.i(TAG, "SUCCESS: Initialized with audio source: $source (${getSourceName(source)})")
                            recordInitialized = true
                            usedSource = source
                            break
                        } else {
                            Log.w(TAG, "Audio source $source: state=$state (not initialized)")
                            audioRecord?.release()
                            audioRecord = null
                        }
                    } catch (e: SecurityException) {
                        Log.e(TAG, "SecurityException for source $source: ${e.message}")
                        audioRecord?.release()
                        audioRecord = null
                    } catch (e: Exception) {
                        Log.e(TAG, "Exception for source $source: ${e.message}")
                        audioRecord?.release()
                        audioRecord = null
                    }
                }
                
                if (!recordInitialized || audioRecord == null) {
                    Log.e(TAG, "FAILED: Could not initialize AudioRecord with any source")
                    return false
                }
                
                isRecording = true
                audioRecord?.startRecording()
                
                // Verify recording actually started
                val recordingState = audioRecord?.recordingState
                Log.i(TAG, "Recording state after startRecording(): $recordingState (expected: ${AudioRecord.RECORDSTATE_RECORDING})")
                
                if (recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                    Log.e(TAG, "FAILED: AudioRecord.startRecording() failed (state: $recordingState)")
                    isRecording = false
                    audioRecord?.release()
                    audioRecord = null
                    return false
                }
                
                // Start recording thread
                recordingThread = Thread {
                    writeAudioDataToFile(bufferSize)
                }
                recordingThread?.priority = Thread.MAX_PRIORITY
                recordingThread?.start()
                
                Log.i(TAG, "=== Recording started successfully ===")
                Log.i(TAG, "Source: $usedSource (${getSourceName(usedSource)})")
                Log.i(TAG, "Path: $outputPath")
                return true
                
            } catch (e: SecurityException) {
                Log.e(TAG, "FATAL: SecurityException - ${e.message}")
                e.printStackTrace()
                return false
            } catch (e: Exception) {
                Log.e(TAG, "FATAL: Exception - ${e.message}")
                e.printStackTrace()
                return false
            }
        }
        
        /**
         * Stop recording and save the audio file
         */
        fun stopRecording(): String? {
            if (!isRecording) {
                Log.w(TAG, "Not recording")
                return null
            }
            
            isRecording = false
            
            try {
                audioRecord?.stop()
                audioRecord?.release()
                audioRecord = null
                
                recordingThread?.join(3000)
                recordingThread = null
                
                // Convert raw PCM to WAV
                val wavPath = outputFile?.absolutePath?.replace(".pcm", ".wav")
                    ?: outputFile?.absolutePath + ".wav"
                
                outputFile?.let { pcmFile ->
                    if (pcmFile.exists()) {
                        val fileSize = pcmFile.length()
                        Log.d(TAG, "PCM file size: $fileSize bytes")
                        
                        if (fileSize > 0) {
                            convertPcmToWav(pcmFile, File(wavPath))
                            pcmFile.delete()
                            Log.i(TAG, "Recording stopped and converted: $wavPath")
                            return wavPath
                        } else {
                            Log.e(TAG, "PCM file is empty")
                            pcmFile.delete()
                            return null
                        }
                    }
                }
                
                Log.e(TAG, "Output file doesn't exist")
                return null
                
            } catch (e: Exception) {
                Log.e(TAG, "Error stopping recording: ${e.message}")
                return null
            }
        }
        
        private fun writeAudioDataToFile(bufferSize: Int) {
            val buffer = ByteArray(bufferSize)
            var fos: FileOutputStream? = null
            var totalBytesWritten = 0L
            var maxAmplitude = 0
            var readCount = 0
            var lastLogTime = System.currentTimeMillis()
            
            Log.i(TAG, "Recording thread started, buffer size: $bufferSize")
            
            try {
                fos = FileOutputStream(outputFile)
                Log.i(TAG, "Output file opened: ${outputFile?.absolutePath}")
                
                while (isRecording) {
                    val read = audioRecord?.read(buffer, 0, bufferSize) ?: -1
                    if (read > 0) {
                        fos.write(buffer, 0, read)
                        totalBytesWritten += read
                        readCount++
                        
                        // Calculate max amplitude in this buffer (for 16-bit PCM)
                        for (i in 0 until read step 2) {
                            if (i + 1 < read) {
                                val sample = (buffer[i].toInt() and 0xFF) or (buffer[i + 1].toInt() shl 8)
                                val amplitude = kotlin.math.abs(sample)
                                if (amplitude > maxAmplitude) {
                                    maxAmplitude = amplitude
                                }
                            }
                        }
                        
                        // Log every 2 seconds
                        val now = System.currentTimeMillis()
                        if (now - lastLogTime >= 2000) {
                            Log.i(TAG, "Recording: ${totalBytesWritten / 1024}KB written, reads=$readCount, maxAmp=$maxAmplitude")
                            lastLogTime = now
                            maxAmplitude = 0 // Reset for next interval
                        }
                    } else if (read < 0) {
                        Log.e(TAG, "AudioRecord read error: $read")
                        break
                    }
                }
                
                Log.i(TAG, "Recording loop ended. Total: $totalBytesWritten bytes, $readCount reads")
                
            } catch (e: IOException) {
                Log.e(TAG, "Error writing audio: ${e.message}")
            } finally {
                try {
                    fos?.close()
                    Log.i(TAG, "Output file closed")
                } catch (e: IOException) {
                    Log.e(TAG, "Error closing file: ${e.message}")
                }
            }
        }
        
        private fun convertPcmToWav(pcmFile: File, wavFile: File) {
            try {
                val pcmData = pcmFile.readBytes()
                val wavData = addWavHeader(pcmData)
                wavFile.writeBytes(wavData)
                Log.d(TAG, "WAV file created: ${wavFile.length()} bytes")
            } catch (e: Exception) {
                Log.e(TAG, "Error converting to WAV: ${e.message}")
            }
        }
        
        private fun addWavHeader(pcmData: ByteArray): ByteArray {
            val totalDataLen = pcmData.size + 36
            val channels = 1 // Mono
            val byteRate = SAMPLE_RATE * channels * 2
            
            val header = ByteArray(44)
            val buffer = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN)
            
            // RIFF header
            header[0] = 'R'.code.toByte()
            header[1] = 'I'.code.toByte()
            header[2] = 'F'.code.toByte()
            header[3] = 'F'.code.toByte()
            buffer.putInt(4, totalDataLen)
            header[8] = 'W'.code.toByte()
            header[9] = 'A'.code.toByte()
            header[10] = 'V'.code.toByte()
            header[11] = 'E'.code.toByte()
            
            // fmt subchunk
            header[12] = 'f'.code.toByte()
            header[13] = 'm'.code.toByte()
            header[14] = 't'.code.toByte()
            header[15] = ' '.code.toByte()
            buffer.putInt(16, 16) // Subchunk1Size
            buffer.putShort(20, 1) // AudioFormat (PCM)
            buffer.putShort(22, channels.toShort()) // NumChannels
            buffer.putInt(24, SAMPLE_RATE) // SampleRate
            buffer.putInt(28, byteRate) // ByteRate
            buffer.putShort(32, (channels * 2).toShort()) // BlockAlign
            buffer.putShort(34, 16) // BitsPerSample
            
            // data subchunk
            header[36] = 'd'.code.toByte()
            header[37] = 'a'.code.toByte()
            header[38] = 't'.code.toByte()
            header[39] = 'a'.code.toByte()
            buffer.putInt(40, pcmData.size)
            
            return header + pcmData
        }
        
        private fun getSourceName(source: Int): String {
            return when (source) {
                MediaRecorder.AudioSource.DEFAULT -> "DEFAULT"
                MediaRecorder.AudioSource.MIC -> "MIC"
                MediaRecorder.AudioSource.VOICE_UPLINK -> "VOICE_UPLINK"
                MediaRecorder.AudioSource.VOICE_DOWNLINK -> "VOICE_DOWNLINK"
                MediaRecorder.AudioSource.VOICE_CALL -> "VOICE_CALL"
                MediaRecorder.AudioSource.CAMCORDER -> "CAMCORDER"
                MediaRecorder.AudioSource.VOICE_RECOGNITION -> "VOICE_RECOGNITION"
                MediaRecorder.AudioSource.VOICE_COMMUNICATION -> "VOICE_COMMUNICATION"
                else -> "UNKNOWN($source)"
            }
        }
    }
    
    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        isServiceEnabled = true
        Log.i(TAG, "Accessibility service connected")
    }
    
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // We don't need to process accessibility events
        // This service is only used for its audio capture capabilities
    }
    
    override fun onInterrupt() {
        Log.i(TAG, "Accessibility service interrupted")
    }
    
    override fun onDestroy() {
        super.onDestroy()
        instance = null
        isServiceEnabled = false
        
        // Stop recording if active
        if (isRecording) {
            stopRecording()
        }
        
        Log.i(TAG, "Accessibility service destroyed")
    }
}
