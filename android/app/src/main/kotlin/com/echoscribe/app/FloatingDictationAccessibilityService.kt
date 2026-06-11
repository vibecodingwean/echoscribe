package com.echoscribe.app

import android.Manifest
import android.accessibilityservice.AccessibilityService
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.media.MediaRecorder
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.text.InputType
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.core.content.ContextCompat
import java.io.File
import kotlin.math.abs

class FloatingDictationAccessibilityService : AccessibilityService() {
    private enum class UiState {
        Idle,
        Recording,
        Processing,
        Preview,
        Message,
    }

    private enum class OverlayKind {
        Logo,
        Recording,
        Processing,
        Preview,
        Message,
    }

    private lateinit var windowManager: WindowManager
    private val mainHandler = Handler(Looper.getMainLooper())
    private val focusUpdateRunnable = Runnable { updateFocusedNodeNow() }
    private val clearTouchRunnable = Runnable {
        overlayTouchActive = false
        scheduleFocusUpdate()
    }
    private val messageResetRunnable = Runnable { resetToIdle() }
    private val configReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == ACTION_CONFIG_CHANGED) {
                handleConfigChanged()
            }
        }
    }
    private var overlayView: View? = null
    private var overlayAttached = false
    private var currentOverlayKind: OverlayKind? = null
    private var processingAnimators = mutableListOf<ObjectAnimator>()
    private var layoutParams: WindowManager.LayoutParams? = null
    private var focusedNode: AccessibilityNodeInfo? = null
    private var uiState = UiState.Idle
    private var previewText = ""
    private var messageText = ""
    private var recorder: MediaRecorder? = null
    private var recordingFile: File? = null
    private var overlayTouchActive = false

    override fun onServiceConnected() {
        super.onServiceConnected()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        ContextCompat.registerReceiver(
            this,
            configReceiver,
            IntentFilter(ACTION_CONFIG_CHANGED),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        createNotificationChannel()
        updateFocusedNode()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.packageName?.toString() == packageName) return
        when (event?.eventType) {
            AccessibilityEvent.TYPE_VIEW_FOCUSED,
            AccessibilityEvent.TYPE_VIEW_TEXT_SELECTION_CHANGED,
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED,
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED -> scheduleFocusUpdate()
        }
    }

    override fun onInterrupt() {
        stopRecordingSilently()
        removeOverlay()
    }

    override fun onDestroy() {
        stopRecordingSilently()
        removeOverlay()
        runCatching { unregisterReceiver(configReceiver) }
        focusedNode = null
        super.onDestroy()
    }

    private fun handleConfigChanged() {
        val config = NativeDictationConfigStore(this).load()
        if (config?.enabled == false) {
            stopRecordingSilently()
            previewText = ""
            messageText = ""
            uiState = UiState.Idle
            removeOverlay()
            return
        }
        scheduleFocusUpdate(delayMs = 0L)
    }

    private fun scheduleFocusUpdate(delayMs: Long = 80L) {
        if (uiState != UiState.Idle) return
        mainHandler.removeCallbacks(focusUpdateRunnable)
        mainHandler.postDelayed(focusUpdateRunnable, if (overlayTouchActive) 180L else delayMs)
    }

    private fun updateFocusedNode() {
        scheduleFocusUpdate(delayMs = 0L)
    }

    private fun updateFocusedNodeNow() {
        if (uiState != UiState.Idle || overlayTouchActive) {
            return
        }
        val root = rootInActiveWindow
        val candidate = root?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        focusedNode = if (candidate != null && isSafeEditableNode(candidate)) candidate else null
        if (focusedNode == null && root != null) {
            focusedNode = findFocusedEditableNode(root)
        }
        showOrHideOverlay()
    }

    private fun showOrHideOverlay() {
        if (!Settings.canDrawOverlays(this)) {
            removeOverlay()
            return
        }
        val config = NativeDictationConfigStore(this).load()
        if (config?.enabled == false) {
            removeOverlay()
            return
        }
        val shouldShow = uiState != UiState.Idle || focusedNode != null
        if (!shouldShow) {
            removeOverlay()
            return
        }
        renderOverlay()
    }

    private fun renderOverlay() {
        if (!Settings.canDrawOverlays(this)) return
        val params = layoutParams ?: createLayoutParams().also { layoutParams = it }
        val kind = overlayKind()
        configureLayoutParams(params, kind)
        if (overlayAttached && currentOverlayKind == kind) {
            updateOverlayContent()
            runCatching { windowManager.updateViewLayout(overlayView, params) }
            return
        }
        if (overlayAttached) {
            stopProcessingAnimation()
            runCatching { windowManager.removeView(overlayView) }
            overlayAttached = false
        }
        overlayView = when (uiState) {
            UiState.Preview -> buildPreviewView()
            UiState.Message -> buildMessageView()
            UiState.Recording -> buildRecordingView()
            UiState.Processing -> buildProcessingView()
            UiState.Idle -> buildLogoView()
        }
        windowManager.addView(overlayView, params)
        overlayAttached = true
        currentOverlayKind = kind
    }

    private fun removeOverlay() {
        if (!overlayAttached) return
        stopProcessingAnimation()
        runCatching { windowManager.removeView(overlayView) }
        overlayAttached = false
        overlayView = null
        currentOverlayKind = null
    }

    private fun overlayKind(): OverlayKind {
        return when (uiState) {
            UiState.Preview -> OverlayKind.Preview
            UiState.Message -> OverlayKind.Message
            UiState.Recording -> OverlayKind.Recording
            UiState.Processing -> OverlayKind.Processing
            UiState.Idle -> OverlayKind.Logo
        }
    }

    private fun updateOverlayContent() {
        when (currentOverlayKind) {
            OverlayKind.Message -> {
                overlayView?.findViewWithTag<TextView>(messageTextTag)?.text = messageText
            }
            OverlayKind.Preview -> {
                overlayView?.findViewWithTag<TextView>(previewTextTag)?.text = previewText
            }
            OverlayKind.Logo,
            OverlayKind.Recording,
            OverlayKind.Processing,
            null -> Unit
        }
    }

    private fun configureLayoutParams(params: WindowManager.LayoutParams, kind: OverlayKind) {
        when (kind) {
            OverlayKind.Message -> {
                params.width = WindowManager.LayoutParams.WRAP_CONTENT
                params.height = WindowManager.LayoutParams.WRAP_CONTENT
                params.gravity = Gravity.CENTER
                params.x = 0
                params.y = 0
            }
            OverlayKind.Preview -> {
                val availableWidth = resources.displayMetrics.widthPixels - dp(32)
                params.width = if (availableWidth > 0) {
                    minOf(availableWidth, dp(430))
                } else {
                    WindowManager.LayoutParams.WRAP_CONTENT
                }
                params.height = WindowManager.LayoutParams.WRAP_CONTENT
                params.gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                params.x = 0
                params.y = dp(56)
            }
            OverlayKind.Logo -> {
                val prefs = getSharedPreferences("floating_dictation_position", MODE_PRIVATE)
                params.width = dp(58)
                params.height = dp(58)
                params.gravity = Gravity.TOP or Gravity.START
                params.x = prefs.getInt("x", dp(24))
                params.y = prefs.getInt("y", dp(180))
            }
            OverlayKind.Recording,
            OverlayKind.Processing -> {
                val prefs = getSharedPreferences("floating_dictation_position", MODE_PRIVATE)
                params.width = dp(58)
                params.height = dp(58)
                params.gravity = Gravity.TOP or Gravity.START
                params.x = prefs.getInt("x", dp(24))
                params.y = prefs.getInt("y", dp(180))
            }
        }
    }

    private fun createLayoutParams(): WindowManager.LayoutParams {
        val prefs = getSharedPreferences("floating_dictation_position", MODE_PRIVATE)
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        return WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            android.graphics.PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = prefs.getInt("x", dp(24))
            y = prefs.getInt("y", dp(180))
        }
    }

    private fun buildLogoView(): View {
        val image = ImageView(this).apply {
            setImageResource(R.drawable.floating_dictation_logo)
            scaleType = ImageView.ScaleType.FIT_CENTER
            elevation = dp(8).toFloat()
            val size = dp(58)
            minimumWidth = size
            minimumHeight = size
            setPadding(0, 0, 0, 0)
        }
        attachDragAndTap(image) { onPrimaryTap() }
        return image
    }

    private fun buildRecordingView(): View {
        val text = TextView(this).apply {
            text = "Stop"
            setTextColor(Color.WHITE)
            textSize = 14f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            minWidth = dp(58)
            minHeight = dp(58)
            background = rounded(0xFFD93025.toInt(), dp(29).toFloat())
            elevation = dp(8).toFloat()
            setPadding(dp(10), dp(8), dp(10), dp(8))
        }
        attachDragAndTap(text) { onPrimaryTap() }
        return text
    }

    private fun buildProcessingView(): View {
        stopProcessingAnimation()
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            background = rounded(0xFF2563EB.toInt(), dp(29).toFloat())
            elevation = dp(8).toFloat()
            minimumWidth = dp(58)
            minimumHeight = dp(58)
            setPadding(dp(12), dp(8), dp(12), dp(8))
        }
        repeat(3) { index ->
            val dot = TextView(this).apply {
                text = "•"
                setTextColor(Color.WHITE)
                textSize = 24f
                alpha = 0.35f
                gravity = Gravity.CENTER
                setPadding(dp(1), 0, dp(1), dp(2))
            }
            container.addView(dot)
            val animator = ObjectAnimator.ofFloat(dot, View.ALPHA, 0.35f, 1f, 0.35f).apply {
                duration = 900L
                startDelay = (index * 140L)
                repeatCount = ValueAnimator.INFINITE
                repeatMode = ValueAnimator.RESTART
                start()
            }
            processingAnimators.add(animator)
        }
        attachDragAndTap(container) { onPrimaryTap() }
        return container
    }

    private fun stopProcessingAnimation() {
        processingAnimators.forEach { animator ->
            runCatching { animator.cancel() }
        }
        processingAnimators.clear()
    }

    private fun buildMessageView(): View {
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = rounded(0xFF111827.toInt(), dp(12).toFloat())
            elevation = dp(8).toFloat()
            setPadding(dp(18), dp(14), dp(18), dp(14))
        }
        val label = TextView(this).apply {
            text = messageText
            tag = messageTextTag
            setTextColor(Color.WHITE)
            textSize = 14f
            gravity = Gravity.CENTER
            maxWidth = dp(300)
        }
        container.addView(label)
        attachDragAndTap(container) { resetToIdle() }
        return container
    }

    private fun buildPreviewView(): View {
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = roundedWithStroke(
                color = 0xFFF7F8FA.toInt(),
                radius = dp(20).toFloat(),
                strokeColor = 0xFFE7E7FF.toInt(),
                strokeWidth = dp(1),
            )
            elevation = dp(12).toFloat()
            setPadding(dp(14), dp(12), dp(14), dp(14))
        }
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, 0, 0, dp(12))
        }
        val headerIcon = ImageView(this).apply {
            setImageResource(R.drawable.floating_dictation_logo)
            scaleType = ImageView.ScaleType.FIT_CENTER
        }
        header.addView(
            headerIcon,
            LinearLayout.LayoutParams(dp(36), dp(36)).apply {
                marginEnd = dp(10)
            },
        )
        val titleColumn = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }
        titleColumn.addView(
            TextView(this).apply {
                text = "Echo Scribe"
                setTextColor(0xFF17174A.toInt())
                typeface = Typeface.DEFAULT_BOLD
                textSize = 15f
                includeFontPadding = false
            },
        )
        titleColumn.addView(
            TextView(this).apply {
                text = "Review dictation"
                setTextColor(0xFF6C7A90.toInt())
                textSize = 12f
                includeFontPadding = false
                setPadding(0, dp(3), 0, 0)
            },
        )
        header.addView(titleColumn)
        val preview = TextView(this).apply {
            text = previewText
            tag = previewTextTag
            setTextColor(0xFF16181D.toInt())
            textSize = 14f
            setLineSpacing(dp(2).toFloat(), 1.0f)
        }
        val textScroll = MaxHeightScrollView(this, maxPreviewTextHeight()).apply {
            isFillViewport = false
            addView(
                preview,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                ),
            )
        }
        val textFrame = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = roundedWithStroke(
                color = Color.WHITE,
                radius = dp(14).toFloat(),
                strokeColor = 0x1F5B5BD6,
                strokeWidth = dp(1),
            )
            setPadding(dp(12), dp(10), dp(12), dp(10))
        }
        textFrame.addView(
            textScroll,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )
        val buttons = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.END
            setPadding(0, dp(12), 0, 0)
        }
        buttons.addView(
            actionButton("Cancel", ButtonStyle.Secondary) { resetToIdle() },
            actionButtonLayout(hasStartMargin = false),
        )
        buttons.addView(
            actionButton("Retry", ButtonStyle.Tonal) {
                previewText = ""
                startRecording()
            },
            actionButtonLayout(hasStartMargin = true),
        )
        buttons.addView(
            actionButton("Insert", ButtonStyle.Primary) { insertPreviewText() },
            actionButtonLayout(hasStartMargin = true),
        )
        container.addView(header)
        container.addView(
            textFrame,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )
        container.addView(buttons)
        return container
    }

    private enum class ButtonStyle {
        Secondary,
        Tonal,
        Primary,
    }

    private fun actionButton(label: String, style: ButtonStyle, onClick: () -> Unit): Button {
        return Button(this).apply {
            text = label
            textSize = 12f
            minHeight = 0
            minWidth = dp(74)
            minimumHeight = 0
            minimumWidth = dp(74)
            setAllCaps(false)
            includeFontPadding = false
            typeface = Typeface.DEFAULT_BOLD
            setPadding(dp(14), 0, dp(14), 0)
            when (style) {
                ButtonStyle.Primary -> {
                    setTextColor(Color.WHITE)
                    background = rounded(0xFF5B5BD6.toInt(), dp(10).toFloat())
                }
                ButtonStyle.Tonal -> {
                    setTextColor(0xFF17174A.toInt())
                    background = rounded(0xFFE7E7FF.toInt(), dp(10).toFloat())
                }
                ButtonStyle.Secondary -> {
                    setTextColor(0xFF6C7A90.toInt())
                    background = roundedWithStroke(
                        color = Color.WHITE,
                        radius = dp(10).toFloat(),
                        strokeColor = 0xFFE1E4EE.toInt(),
                        strokeWidth = dp(1),
                    )
                }
            }
            setOnClickListener { onClick() }
        }
    }

    private fun actionButtonLayout(hasStartMargin: Boolean): LinearLayout.LayoutParams {
        return LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            dp(40),
        ).apply {
            if (hasStartMargin) marginStart = dp(8)
        }
    }

    private fun attachDragAndTap(view: View, onTap: () -> Unit) {
        var initialX = 0
        var initialY = 0
        var initialTouchX = 0f
        var initialTouchY = 0f
        var moved = false
        view.setOnTouchListener { _, event ->
            val params = layoutParams ?: return@setOnTouchListener false
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    overlayTouchActive = true
                    mainHandler.removeCallbacks(clearTouchRunnable)
                    initialX = params.x
                    initialY = params.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    moved = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - initialTouchX
                    val dy = event.rawY - initialTouchY
                    if (abs(dx) > dp(4) || abs(dy) > dp(4)) moved = true
                    params.x = initialX + dx.toInt()
                    params.y = initialY + dy.toInt()
                    runCatching { windowManager.updateViewLayout(overlayView, params) }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    savePosition(params)
                    if (!moved) onTap()
                    finishOverlayTouch()
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    finishOverlayTouch()
                    true
                }
                else -> false
            }
        }
    }

    private fun finishOverlayTouch() {
        mainHandler.removeCallbacks(clearTouchRunnable)
        mainHandler.postDelayed(clearTouchRunnable, 140L)
    }

    private fun onPrimaryTap() {
        when (uiState) {
            UiState.Idle, UiState.Message -> startRecording()
            UiState.Recording -> stopAndProcessRecording()
            UiState.Processing, UiState.Preview -> Unit
        }
    }

    private fun startRecording() {
        val config = NativeDictationConfigStore(this).load()
        if (config?.enabled == false) {
            removeOverlay()
            return
        }
        if (config == null || !config.isReadyForDictation()) {
            showMessage(if (config?.provider == "anthropic") "Speech input not supported for Claude" else "Open Echo Scribe settings")
            return
        }
        if (!hasMicrophonePermission()) {
            showMessage("Microphone permission required")
            return
        }
        if (focusedNode == null || !isSafeEditableNode(focusedNode!!)) {
            showMessage("Select a text field first")
            return
        }

        if (config.provider == "localAi") {
            uiState = UiState.Processing
            renderOverlay()
            Thread {
                try {
                    NativeDictationApiClient(config).preflightLocalAi()
                    mainHandler.post { startRecordingNow() }
                } catch (e: Exception) {
                    mainHandler.post {
                        showMessage(e.message ?: "Local AI is not reachable")
                    }
                }
            }.start()
            return
        }

        startRecordingNow()
    }

    private fun startRecordingNow() {
        if (!hasMicrophonePermission()) {
            showMessage("Microphone permission required")
            return
        }
        if (focusedNode == null || !isSafeEditableNode(focusedNode!!)) {
            showMessage("Select a text field first")
            return
        }

        try {
            previewText = ""
            recordingFile = File(cacheDir, "floating_dictation_${System.currentTimeMillis()}.m4a")
            startMicForeground()
            recorder = newRecorder().apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setAudioSamplingRate(44_100)
                setAudioEncodingBitRate(128_000)
                setOutputFile(recordingFile!!.absolutePath)
                prepare()
                start()
            }
            uiState = UiState.Recording
            renderOverlay()
        } catch (e: Exception) {
            stopRecordingSilently()
            showMessage(e.message ?: "Recording failed")
        }
    }

    private fun stopAndProcessRecording() {
        val file = recordingFile
        stopRecordingSilently()
        if (file == null || !file.exists() || file.length() == 0L) {
            showMessage("Recording failed")
            return
        }
        val config = NativeDictationConfigStore(this).load()
        if (config == null || !config.isReadyForDictation()) {
            showMessage("Open Echo Scribe settings")
            return
        }
        uiState = UiState.Processing
        renderOverlay()
        Thread {
            try {
                val client = NativeDictationApiClient(config)
                val rawText = client.transcribe(file)
                val formatted = client.format(rawText)
                mainHandler.post {
                    previewText = formatted
                    uiState = UiState.Preview
                    renderOverlay()
                }
            } catch (e: Exception) {
                mainHandler.post { showMessage(e.message ?: "Dictation failed") }
            } finally {
                runCatching { file.delete() }
            }
        }.start()
    }

    private fun insertPreviewText() {
        val text = previewText.trim()
        if (text.isBlank()) {
            resetToIdle()
            return
        }
        val node = focusedNode ?: rootInActiveWindow?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        if (node == null || !isSafeEditableNode(node)) {
            showMessage("Select a text field first")
            return
        }
        val clipboard = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("Echo Scribe dictation", text))
        node.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
        val pasted = node.performAction(AccessibilityNodeInfo.ACTION_PASTE)
        if (!pasted) {
            showMessage("This field does not accept paste")
            return
        }
        resetToIdle()
    }

    private fun resetToIdle() {
        mainHandler.removeCallbacks(messageResetRunnable)
        previewText = ""
        messageText = ""
        uiState = UiState.Idle
        if (overlayTouchActive) {
            scheduleFocusUpdate(180L)
        } else {
            updateFocusedNodeNow()
        }
    }

    private fun showMessage(message: String) {
        messageText = message.take(160)
        uiState = UiState.Message
        renderOverlay()
        mainHandler.removeCallbacks(messageResetRunnable)
        mainHandler.postDelayed(messageResetRunnable, 2800)
    }

    private fun stopRecordingSilently() {
        runCatching { recorder?.stop() }
        runCatching { recorder?.reset() }
        runCatching { recorder?.release() }
        recorder = null
        runCatching { stopMicForeground() }
    }

    private fun newRecorder(): MediaRecorder {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(this)
        } else {
            @Suppress("DEPRECATION")
            MediaRecorder()
        }
    }

    private fun isSafeEditableNode(node: AccessibilityNodeInfo): Boolean {
        if (!node.isEnabled || !node.isEditable) return false
        val packageName = node.packageName?.toString()?.lowercase().orEmpty()
        if (denylistedPackages.any { packageName.contains(it) }) return false

        val inputType = node.inputType
        val inputClass = inputType and InputType.TYPE_MASK_CLASS
        val variation = inputType and InputType.TYPE_MASK_VARIATION
        if (inputClass == InputType.TYPE_CLASS_PHONE) return false
        if (inputClass == InputType.TYPE_CLASS_TEXT &&
            (variation == InputType.TYPE_TEXT_VARIATION_PASSWORD ||
                variation == InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD ||
                variation == InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD)
        ) {
            return false
        }
        if (inputClass == InputType.TYPE_CLASS_NUMBER &&
            variation == InputType.TYPE_NUMBER_VARIATION_PASSWORD
        ) {
            return false
        }

        val metadata = listOfNotNull(
            node.viewIdResourceName,
            node.hintText?.toString(),
            node.contentDescription?.toString(),
        ).joinToString(" ").lowercase()
        return denylistedFieldHints.none { metadata.contains(it) }
    }

    private fun findFocusedEditableNode(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        if (node.isFocused && isSafeEditableNode(node)) return node

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val match = findFocusedEditableNode(child)
            if (match != null) return match
        }
        return null
    }

    private fun hasMicrophonePermission(): Boolean {
        return ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun startMicForeground() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) createNotificationChannel()
        startForeground(notificationId, buildNotification())
    }

    private fun stopMicForeground() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun buildNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, notificationChannelId)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("Echo Scribe")
                .setContentText("Floating dictation is recording")
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("Echo Scribe")
                .setContentText("Floating dictation is recording")
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .build()
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            notificationChannelId,
            "Floating Dictation",
            NotificationManager.IMPORTANCE_LOW,
        )
        manager.createNotificationChannel(channel)
    }

    private fun savePosition(params: WindowManager.LayoutParams) {
        getSharedPreferences("floating_dictation_position", MODE_PRIVATE)
            .edit()
            .putInt("x", params.x)
            .putInt("y", params.y)
            .apply()
    }

    private fun rounded(color: Int, radius: Float): GradientDrawable {
        return GradientDrawable().apply {
            setColor(color)
            cornerRadius = radius
        }
    }

    private fun roundedWithStroke(
        color: Int,
        radius: Float,
        strokeColor: Int,
        strokeWidth: Int,
    ): GradientDrawable {
        return GradientDrawable().apply {
            setColor(color)
            cornerRadius = radius
            setStroke(strokeWidth, strokeColor)
        }
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }

    private fun maxPreviewTextHeight(): Int {
        val screenHeight = resources.displayMetrics.heightPixels
        return minOf((screenHeight * 0.42f).toInt(), dp(360)).coerceAtLeast(dp(140))
    }

    private class MaxHeightScrollView(
        context: Context,
        private val maxHeightPx: Int,
    ) : ScrollView(context) {
        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            val limitedHeightSpec = View.MeasureSpec.makeMeasureSpec(
                maxHeightPx,
                View.MeasureSpec.AT_MOST,
            )
            super.onMeasure(widthMeasureSpec, limitedHeightSpec)
        }
    }

    companion object {
        const val ACTION_CONFIG_CHANGED = "com.echoscribe.app.FLOATING_DICTATION_CONFIG_CHANGED"
        private const val notificationChannelId = "floating_dictation_recording"
        private const val notificationId = 7301
        private const val messageTextTag = "floating_dictation_message_text"
        private const val previewTextTag = "floating_dictation_preview_text"
        private val denylistedPackages = listOf(
            "bank",
            "paypal",
            "venmo",
            "cashapp",
            "revolut",
            "wise",
            "n26",
            "coinbase",
            "binance",
            "klarna",
            "stripe",
            "wallet",
            "gpay",
        )
        private val denylistedFieldHints = listOf(
            "password",
            "passcode",
            "pin",
            "cvv",
            "cvc",
            "credit",
            "card",
            "iban",
            "bank",
            "security code",
            "phone",
            "tel",
        )
    }
}
