package com.example.meeting_app

import android.animation.ArgbEvaluator
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import android.view.WindowManager

class CallOverlayService : Service() {
    
    companion object {
        private const val TAG = "CallOverlayService"
        
        private var instance: CallOverlayService? = null
        private var overlayView: View? = null
        private var isRecording = false
        private var recordingSeconds = 0
        
        var onRecordingToggle: ((Boolean) -> Unit)? = null
        var onOverlayClosed: (() -> Unit)? = null
        
        fun showOverlay(context: Context): Boolean {
            if (!Settings.canDrawOverlays(context)) {
                Log.e(TAG, "No overlay permission")
                return false
            }
            
            if (overlayView != null) {
                Log.d(TAG, "Overlay already showing")
                return true
            }
            
            try {
                val intent = Intent(context, CallOverlayService::class.java)
                intent.action = "SHOW"
                context.startService(intent)
                return true
            } catch (e: Exception) {
                Log.e(TAG, "Error starting overlay service: ${e.message}")
                return false
            }
        }
        
        fun hideOverlay(context: Context) {
            try {
                val intent = Intent(context, CallOverlayService::class.java)
                intent.action = "HIDE"
                context.startService(intent)
            } catch (e: Exception) {
                Log.e(TAG, "Error hiding overlay: ${e.message}")
            }
        }
        
        fun updateRecordingState(recording: Boolean, seconds: Int = 0) {
            isRecording = recording
            recordingSeconds = seconds
            instance?.updateUI()
        }
    }
    
    private lateinit var windowManager: WindowManager
    private var params: WindowManager.LayoutParams? = null
    private var pulseAnimator: ValueAnimator? = null
    private var recordButton: View? = null
    private var recordButtonOuter: View? = null
    private var textView: TextView? = null
    private var subtitleView: TextView? = null
    private var containerBackground: GradientDrawable? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    
    // Colors
    private val colorPrimary = Color.parseColor("#6366F1") // Indigo
    private val colorPrimaryDark = Color.parseColor("#4F46E5")
    private val colorRecording = Color.parseColor("#EF4444") // Red
    private val colorRecordingDark = Color.parseColor("#DC2626")
    private val colorSurface = Color.parseColor("#1F2937") // Dark gray
    private val colorSurfaceLight = Color.parseColor("#374151")
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    override fun onCreate() {
        super.onCreate()
        instance = this
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        Log.d(TAG, "Service created")
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            "SHOW" -> createOverlay()
            "HIDE" -> removeOverlay()
        }
        return START_NOT_STICKY
    }
    
    private fun createOverlay() {
        if (overlayView != null) return
        
        Log.d(TAG, "Creating overlay")
        
        // Create the overlay view programmatically
        overlayView = createOverlayView()
        
        val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        
        params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            layoutFlag,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.END
            x = dpToPx(16)
            y = dpToPx(100)
        }
        
        try {
            windowManager.addView(overlayView, params)
            Log.d(TAG, "Overlay added successfully")
            
            // Start entrance animation
            overlayView?.alpha = 0f
            overlayView?.scaleX = 0.8f
            overlayView?.scaleY = 0.8f
            overlayView?.animate()
                ?.alpha(1f)
                ?.scaleX(1f)
                ?.scaleY(1f)
                ?.setDuration(200)
                ?.setInterpolator(AccelerateDecelerateInterpolator())
                ?.start()
                
        } catch (e: Exception) {
            Log.e(TAG, "Error adding overlay: ${e.message}")
            overlayView = null
        }
    }
    
    private fun dpToPx(dp: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            dp.toFloat(),
            resources.displayMetrics
        ).toInt()
    }
    
    private fun createOverlayView(): View {
        // Main container with rounded corners and gradient
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dpToPx(12), dpToPx(10), dpToPx(14), dpToPx(10))
            elevation = dpToPx(8).toFloat()
            
            // Create gradient background
            containerBackground = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(28).toFloat()
                setColor(colorSurface)
                setStroke(dpToPx(1), colorSurfaceLight)
            }
            background = containerBackground
        }
        
        // Record button container (for outer ring effect)
        val recordButtonContainer = FrameLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(dpToPx(44), dpToPx(44)).apply {
                marginEnd = dpToPx(10)
            }
        }
        
        // Outer ring (pulsing glow when recording)
        recordButtonOuter = View(this).apply {
            layoutParams = FrameLayout.LayoutParams(dpToPx(44), dpToPx(44)).apply {
                gravity = Gravity.CENTER
            }
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.TRANSPARENT)
                setStroke(dpToPx(2), colorPrimary)
            }
            alpha = 0.5f
        }
        
        // Inner record button
        recordButton = View(this).apply {
            layoutParams = FrameLayout.LayoutParams(dpToPx(36), dpToPx(36)).apply {
                gravity = Gravity.CENTER
            }
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                colors = intArrayOf(colorPrimary, colorPrimaryDark)
                gradientType = GradientDrawable.RADIAL_GRADIENT
                gradientRadius = dpToPx(36).toFloat()
            }
            elevation = dpToPx(4).toFloat()
        }
        
        recordButtonContainer.addView(recordButtonOuter)
        recordButtonContainer.addView(recordButton)
        
        // Text container (vertical layout for title + subtitle)
        val textContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                marginEnd = dpToPx(8)
            }
        }
        
        // Main text (Record / Timer)
        textView = TextView(this).apply {
            text = "Tap to Record"
            textSize = 14f
            setTextColor(Color.WHITE)
            typeface = android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.NORMAL)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }
        
        // Subtitle with speaker hint
        subtitleView = TextView(this).apply {
            text = "\uD83D\uDD0A Enable speaker mode"  // Speaker emoji
            textSize = 10f
            setTextColor(Color.parseColor("#FCD34D"))  // Yellow/amber color for attention
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }
        
        textContainer.addView(textView)
        textContainer.addView(subtitleView)
        
        // Close button with icon-like appearance
        val closeButton = TextView(this).apply {
            text = "×"
            textSize = 22f
            setTextColor(Color.parseColor("#6B7280"))
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(dpToPx(32), dpToPx(32)).apply {
                gravity = Gravity.CENTER_VERTICAL
            }
            
            // Circular background on press
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.TRANSPARENT)
            }
            
            setOnClickListener {
                // Animate out then close
                overlayView?.animate()
                    ?.alpha(0f)
                    ?.scaleX(0.8f)
                    ?.scaleY(0.8f)
                    ?.setDuration(150)
                    ?.withEndAction {
                        onOverlayClosed?.invoke()
                        removeOverlay()
                    }
                    ?.start()
            }
        }
        
        container.addView(recordButtonContainer)
        container.addView(textContainer)
        container.addView(closeButton)
        
        // Handle touch for dragging and clicking
        var initialX = 0
        var initialY = 0
        var initialTouchX = 0f
        var initialTouchY = 0f
        var isDragging = false
        var touchStartTime = 0L
        
        container.setOnTouchListener { view, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params?.x ?: 0
                    initialY = params?.y ?: 0
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    isDragging = false
                    touchStartTime = System.currentTimeMillis()
                    
                    // Scale down feedback
                    view.animate().scaleX(0.95f).scaleY(0.95f).setDuration(100).start()
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - initialTouchX
                    val dy = event.rawY - initialTouchY
                    if (Math.abs(dx) > 10 || Math.abs(dy) > 10) {
                        isDragging = true
                        view.animate().scaleX(1f).scaleY(1f).setDuration(100).start()
                    }
                    if (isDragging) {
                        params?.x = initialX - dx.toInt() // Inverted for END gravity
                        params?.y = initialY + dy.toInt()
                        try {
                            windowManager.updateViewLayout(overlayView, params)
                        } catch (e: Exception) {
                            Log.e(TAG, "Error updating layout: ${e.message}")
                        }
                    }
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    view.animate().scaleX(1f).scaleY(1f).setDuration(100).start()
                    
                    if (!isDragging && System.currentTimeMillis() - touchStartTime < 300) {
                        // Toggle recording
                        onRecordingToggle?.invoke(!isRecording)
                    }
                    true
                }
                else -> false
            }
        }
        
        return container
    }
    
    private fun updateUI() {
        mainHandler.post {
            if (isRecording) {
                // Update to recording state
                val mins = recordingSeconds / 60
                val secs = recordingSeconds % 60
                textView?.text = String.format("%02d:%02d", mins, secs)
                textView?.setTextColor(colorRecording)
                
                // Change button to red (stop button appearance)
                (recordButton?.background as? GradientDrawable)?.apply {
                    colors = intArrayOf(colorRecording, colorRecordingDark)
                }
                
                // Update outer ring to red
                (recordButtonOuter?.background as? GradientDrawable)?.setStroke(dpToPx(2), colorRecording)
                
                // Start pulse animation if not running
                if (pulseAnimator == null || !pulseAnimator!!.isRunning) {
                    startPulseAnimation()
                }
                
                // Update container border to red
                containerBackground?.setStroke(dpToPx(1), colorRecording)
                
            } else {
                // Update to idle state
                textView?.text = "Tap to Record"
                textView?.setTextColor(Color.WHITE)
                
                // Change button back to indigo
                (recordButton?.background as? GradientDrawable)?.apply {
                    colors = intArrayOf(colorPrimary, colorPrimaryDark)
                }
                
                // Update outer ring to indigo
                (recordButtonOuter?.background as? GradientDrawable)?.setStroke(dpToPx(2), colorPrimary)
                recordButtonOuter?.alpha = 0.5f
                
                // Stop pulse animation
                stopPulseAnimation()
                
                // Reset container border
                containerBackground?.setStroke(dpToPx(1), colorSurfaceLight)
            }
        }
    }
    
    private fun startPulseAnimation() {
        pulseAnimator?.cancel()
        
        pulseAnimator = ValueAnimator.ofFloat(0.3f, 1f).apply {
            duration = 800
            repeatCount = ValueAnimator.INFINITE
            repeatMode = ValueAnimator.REVERSE
            interpolator = AccelerateDecelerateInterpolator()
            
            addUpdateListener { animator ->
                val value = animator.animatedValue as Float
                recordButtonOuter?.alpha = value
                recordButtonOuter?.scaleX = 1f + (value * 0.15f)
                recordButtonOuter?.scaleY = 1f + (value * 0.15f)
            }
            
            start()
        }
    }
    
    private fun stopPulseAnimation() {
        pulseAnimator?.cancel()
        pulseAnimator = null
        recordButtonOuter?.alpha = 0.5f
        recordButtonOuter?.scaleX = 1f
        recordButtonOuter?.scaleY = 1f
    }
    
    private fun removeOverlay() {
        stopPulseAnimation()
        
        overlayView?.let {
            try {
                windowManager.removeView(it)
                Log.d(TAG, "Overlay removed")
            } catch (e: Exception) {
                Log.e(TAG, "Error removing overlay: ${e.message}")
            }
            overlayView = null
        }
        
        recordButton = null
        recordButtonOuter = null
        textView = null
        containerBackground = null
        isRecording = false
        recordingSeconds = 0
        stopSelf()
    }
    
    override fun onDestroy() {
        removeOverlay()
        instance = null
        super.onDestroy()
    }
}
