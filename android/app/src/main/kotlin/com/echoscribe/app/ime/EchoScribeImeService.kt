package com.echoscribe.app.ime

import android.Manifest
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.PorterDuff
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.InsetDrawable
import android.graphics.drawable.StateListDrawable
import android.inputmethodservice.InputMethodService
import android.media.AudioAttributes
import android.media.MediaRecorder
import android.media.SoundPool
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.ExtractedTextRequest
import android.view.inputmethod.InputConnection
import android.view.inputmethod.InputContentInfo
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.PopupWindow
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.core.content.ContextCompat
import com.echoscribe.app.NativeDictationApiClient
import com.echoscribe.app.NativeDictationConfig
import com.echoscribe.app.R
import com.echoscribe.app.NativeDictationConfigStore
import java.io.File

class EchoScribeImeService : InputMethodService() {
    private enum class Layer { Letters, Symbols }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val clipboardStore by lazy { ImeClipboardStore(this) }
    private val recentEmojiStore by lazy { ImeRecentEmojiStore(this) }
    private var config: NativeDictationConfig? = null
    private var root: LinearLayout? = null
    private var contentHost: FrameLayout? = null
    private var suggestionBar: LinearLayout? = null
    private var toolbar: View? = null
    private var clipboardPreviewHost: LinearLayout? = null

    private var capsLock = false
    private var shiftOnce = false
    private var autoCapNext = true
    private var activeLayout = ImeKeyboardLayout.QWERTZ
    private val letterBindings = mutableListOf<LetterBinding>()
    private var shiftVisual: TextView? = null
    private var pendingKey: KeySpec? = null
    private var pendingKeyVisual: TextView? = null
    private var longPressFired = false
    private var accentHoldOriginX = 0f
    private var accentHoldGlyphs: List<String> = emptyList()
    private var accentHoldIndex = 0
    private var accentHoldViews: List<TextView> = emptyList()
    private val longPressRunnable = Runnable {
        val key = pendingKey ?: return@Runnable
        val visual = pendingKeyVisual ?: return@Runnable
        longPressFired = true
        when (key.action) {
            KeyAction.Shift -> {
                val next = ImeShiftState(capsLock, shiftOnce, autoCapNext).longPress()
                capsLock = next.capsLock
                shiftOnce = next.shiftOnce
                autoCapNext = next.autoCapNext
                applyLetterCase()
            }
            else -> {
                val base = key.baseLabel.ifEmpty {
                    (key.action as? KeyAction.CommitChar)?.value?.toString().orEmpty()
                }
                val glyphs = ImeAccentHold.holdGlyphs(base)
                if (glyphs.isNotEmpty()) {
                    showAccentHold(visual, glyphs)
                }
            }
        }
    }
    private var voiceLog: String? = null
    private var layer = Layer.Letters
    private var composing = StringBuilder()
    private var sensitiveField = false
    private var activeSheet: ImeSheetKind? = null
    private var selectedChipId: String? = null
    private var translateTargetCode = "en"
    private var aiResults: List<String> = emptyList()
    private var selectedResultIndex = 0
    private var aiBusy = false
    private var aiError: String? = null
    private var italicPrompt: String? = null

    private var recorder: MediaRecorder? = null
    private var recordingFile: File? = null
    private var isRecording = false
    private var isProcessingVoice = false
    private var accentPopup: PopupWindow? = null
    private var clipboardImageUri: Uri? = null
    private var clipboardImageMime: String? = null
    private var keySoundPool: SoundPool? = null
    private var keyClickId = 0
    private var keyClickReady = false
    private var backspaceHeld = false
    private var backspaceOriginX = 0f
    private var backspaceSwipeWords = 0
    private var spaceCursorArmed = false
    private var spaceOriginX = 0f
    private var spaceOriginY = 0f
    private var spaceCursorBefore = 0
    private var spaceSnapshot = ""
    private var lastCharSteps = 0
    private var lastLineSteps = 0
    private var spaceLoupe: PopupWindow? = null
    private var spaceLoupeText: TextView? = null
    private var statusLine: String? = null
    private var sheetResetPending = false
    private val backspaceRepeatRunnable = object : Runnable {
        override fun run() {
            if (!backspaceHeld) return
            deleteBackward()
            mainHandler.postDelayed(this, 45)
        }
    }
    private val spaceCursorRunnable = Runnable {
        val ic = currentInputConnection ?: return@Runnable
        val before = ic.getTextBeforeCursor(MAX_SOURCE_CHARS, 0)?.toString().orEmpty()
        val after = ic.getTextAfterCursor(MAX_SOURCE_CHARS, 0)?.toString().orEmpty()
        spaceCursorArmed = true
        spaceSnapshot = before + after
        spaceCursorBefore = before.length
        lastCharSteps = 0
        lastLineSteps = 0
        showSpaceLoupe(spaceCursorBefore)
    }

    private val configReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == NativeDictationConfigStore.ACTION_CONFIG_CHANGED) {
                reloadConfig()
                rebuildUi()
            }
        }
    }

    private val clipListener = ClipboardManager.OnPrimaryClipChangedListener {
        val text = readPrimaryClipText()
        if (!text.isNullOrBlank()) {
            clipboardStore.add(text)
        }
        mainHandler.post { refreshSuggestions() }
    }

    override fun onCreate() {
        super.onCreate()
        ContextCompat.registerReceiver(
            this,
            configReceiver,
            IntentFilter(NativeDictationConfigStore.ACTION_CONFIG_CHANGED),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        (getSystemService(CLIPBOARD_SERVICE) as ClipboardManager)
            .addPrimaryClipChangedListener(clipListener)
        reloadConfig()
        ensureKeyClick()
    }

    override fun onDestroy() {
        stopBackspaceRepeat()
        cancelPendingKey()
        dismissAccents()
        stopRecordingSilently()
        runCatching { unregisterReceiver(configReceiver) }
        runCatching {
            (getSystemService(CLIPBOARD_SERVICE) as ClipboardManager)
                .removePrimaryClipChangedListener(clipListener)
        }
        keySoundPool?.release()
        keySoundPool = null
        keyClickReady = false
        super.onDestroy()
    }

    override fun onCreateInputView(): View {
        reloadConfig()
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(COLOR_BG)
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            )
        }
        root = container
        container.setOnApplyWindowInsetsListener { v, insets ->
            v.setPadding(0, 0, 0, navigationBottomInset(insets))
            insets
        }
        rebuildUi()
        container.requestApplyInsets()
        return container
    }

    override fun onStartInput(attribute: EditorInfo?, restarting: Boolean) {
        super.onStartInput(attribute, restarting)
        updateSensitivity(attribute)
        composing.clear()
        if (!restarting) {
            resetShiftState(newField = true)
        }
        if (ImeViewReset.shouldClearSheet(restarting = restarting, sensitiveField = sensitiveField)) {
            activeSheet = null
        }
        if (sensitiveField) {
            stopRecordingSilently()
        }
    }

    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        val wasSensitive = sensitiveField
        updateSensitivity(info)
        if (contentHost == null || wasSensitive != sensitiveField) {
            rebuildUi()
            sheetResetPending = false
        } else if (sheetResetPending) {
            sheetResetPending = false
            renderContent()
            applyLetterCase()
        } else {
            applyLetterCase()
        }
        refreshSuggestions()
    }

    override fun onFinishInputView(finishingInput: Boolean) {
        val reset = ImeViewReset.finishInputView()
        sheetResetPending = activeSheet != null || layer != Layer.Letters
        if (reset.cancelPendingKey) cancelPendingKey()
        if (reset.dismissAccentPopup) dismissAccents()
        stopRecordingSilently()
        if (reset.clearVoiceLog) voiceLog = null
        activeSheet = reset.activeSheet
        if (reset.lettersLayer) layer = Layer.Letters
        spaceCursorArmed = false
        dismissSpaceLoupe()
        statusLine = null
        super.onFinishInputView(finishingInput)
    }

    override fun onComputeInsets(outInsets: Insets) {
        super.onComputeInsets(outInsets)
        val v = root ?: return
        val loc = IntArray(2)
        v.getLocationInWindow(loc)
        if (loc[1] > 0) {
            outInsets.contentTopInsets = loc[1]
            outInsets.visibleTopInsets = loc[1]
        }
    }

    private fun reloadConfig() {
        config = NativeDictationConfigStore(this).load()
        val stored = config?.keyboardLayout
        activeLayout = if (stored == ImeKeyboardLayout.QWERTY || stored == ImeKeyboardLayout.QWERTZ) {
            stored
        } else {
            NativeDictationConfigStore(this).loadKeyboardLayout()
        }
    }

    private fun updateSensitivity(info: EditorInfo?) {
        if (info == null) {
            sensitiveField = false
            return
        }
        val meta = listOfNotNull(info.hintText?.toString(), info.fieldName).joinToString(" ")
        sensitiveField = ImeInputSafety.shouldHideAiAndMic(
            inputType = info.inputType,
            autofillHints = emptyList(),
            hintOrDescription = meta,
        )
    }

    private fun rebuildUi() {
        val container = root ?: return
        container.removeAllViews()
        container.setPadding(0, 0, 0, navigationBottomInset(container.rootWindowInsets))

        if (!sensitiveField) {
            toolbar = buildToolbar()
            container.addView(toolbar)
        } else {
            toolbar = null
            clipboardPreviewHost = null
        }

        suggestionBar = buildSuggestionBar()
        container.addView(suggestionBar)

        val fillAi = when (activeSheet) {
            ImeSheetKind.Grammar, ImeSheetKind.Tone, ImeSheetKind.Translate -> true
            else -> false
        }
        contentHost = FrameLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                if (fillAi) 0 else LinearLayout.LayoutParams.WRAP_CONTENT,
                if (fillAi) 1f else 0f,
            )
        }
        container.addView(contentHost)
        renderContent()
    }

    private fun renderContent() {
        val host = contentHost ?: return
        host.removeAllViews()
        val sheet = activeSheet
        val child = when {
            sheet == null -> buildKeyboard()
            sheet == ImeSheetKind.Emoji -> buildEmojiPanel()
            sheet == ImeSheetKind.Clipboard -> buildClipboardPanel()
            sheet == ImeSheetKind.More -> buildMorePanel()
            else -> buildAiSheet(sheet)
        }
        host.addView(child)
        refreshSuggestions()
    }

    private fun buildToolbar(): View {
        fun tool(
            label: String,
            selected: Boolean = false,
            onLongClick: (() -> Unit)? = null,
            onClick: () -> Unit,
        ): TextView {
            return TextView(this).apply {
                text = label
                setTextColor(COLOR_TEXT)
                textSize = 16f
                gravity = Gravity.CENTER
                minWidth = dp(36)
                minHeight = dp(36)
                setPadding(dp(9), dp(8), dp(9), dp(8))
                background = rounded(if (selected) COLOR_SELECTED else COLOR_TOOL, 12f)
                setOnClickListener { onClick() }
                if (onLongClick != null) {
                    setOnLongClickListener {
                        onLongClick()
                        true
                    }
                }
            }
        }
        fun iconTool(
            iconRes: Int,
            contentDescription: String,
            selected: Boolean = false,
            onLongClick: (() -> Unit)? = null,
            onClick: () -> Unit,
        ): ImageView {
            return ImageView(this).apply {
                setImageResource(iconRes)
                this.contentDescription = contentDescription
                scaleType = ImageView.ScaleType.FIT_CENTER
                adjustViewBounds = true
                minimumWidth = dp(40)
                minimumHeight = dp(40)
                setPadding(dp(4), dp(4), dp(4), dp(4))
                background = rounded(if (selected) COLOR_SELECTED else COLOR_TOOL, 12f)
                layoutParams = LinearLayout.LayoutParams(dp(40), dp(40))
                if (selected) {
                    setColorFilter(COLOR_TEXT, PorterDuff.Mode.SRC_IN)
                } else {
                    clearColorFilter()
                }
                isClickable = true
                isFocusable = true
                setOnClickListener {
                    keyFeedback(this)
                    onClick()
                }
                if (onLongClick != null) {
                    setOnLongClickListener {
                        keyFeedback(this)
                        onLongClick()
                        true
                    }
                }
            }
        }
        val scrollRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(4), dp(4), dp(2), dp(4))
        }
        scrollRow.addView(
            iconTool(
                ImeAiActions.toolbarIconRes(ImeSheetKind.Grammar)!!,
                ImeAiActions.sheetTitle(ImeSheetKind.Grammar),
                ImeAiActions.isToolbarToolSelected(activeSheet, ImeSheetKind.Grammar),
                onLongClick = { runGrammarInPlace() },
            ) {
                openSheet(ImeSheetKind.Grammar, autoRun = false)
            },
        )
        scrollRow.addView(space(3))
        scrollRow.addView(
            iconTool(
                ImeAiActions.toolbarIconRes(ImeSheetKind.Tone)!!,
                ImeAiActions.sheetTitle(ImeSheetKind.Tone),
                ImeAiActions.isToolbarToolSelected(activeSheet, ImeSheetKind.Tone),
            ) {
                openSheet(ImeSheetKind.Tone)
            },
        )
        scrollRow.addView(space(3))
        scrollRow.addView(
            tool(
                ImeAiActions.toolbarIcon(ImeSheetKind.Translate),
                ImeAiActions.isToolbarToolSelected(activeSheet, ImeSheetKind.Translate),
            ) {
                openSheet(ImeSheetKind.Translate)
            },
        )
        scrollRow.addView(space(4))
        scrollRow.addView(View(this).apply {
            layoutParams = LinearLayout.LayoutParams(dp(1), dp(20)).apply { setMargins(dp(1), 0, dp(1), 0) }
            setBackgroundColor(0xFF555555.toInt())
        })
        scrollRow.addView(space(4))
        scrollRow.addView(tool("⧉") { copyCurrentText() })
        scrollRow.addView(space(3))
        scrollRow.addView(
            tool(
                "📋",
                ImeAiActions.isToolbarToolSelected(activeSheet, ImeSheetKind.Clipboard),
            ) { openSheet(ImeSheetKind.Clipboard) }.apply {
                setOnLongClickListener {
                    pastePrimaryClip()
                    true
                }
            },
        )
        scrollRow.addView(space(3))
        val previewHost = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            visibility = View.GONE
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )
        }
        clipboardPreviewHost = previewHost
        scrollRow.addView(previewHost)
        val micLabel = when {
            isProcessingVoice -> "…"
            isRecording -> "■"
            else -> "🎤"
        }
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )
            addView(
                HorizontalScrollView(this@EchoScribeImeService).apply {
                    isHorizontalScrollBarEnabled = true
                    overScrollMode = View.OVER_SCROLL_IF_CONTENT_SCROLLS
                    isFillViewport = false
                    addView(
                        scrollRow,
                        ViewGroup.LayoutParams(
                            ViewGroup.LayoutParams.WRAP_CONTENT,
                            ViewGroup.LayoutParams.WRAP_CONTENT,
                        ),
                    )
                },
                LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
            )
            addView(
                tool(micLabel) { onMicTapped() }.apply {
                    minWidth = dp(56)
                    textSize = 18f
                    setPadding(dp(16), dp(9), dp(16), dp(9))
                    background = rounded(
                        when {
                            isRecording -> 0xFFC4474A.toInt()
                            isProcessingVoice -> COLOR_TOOL
                            else -> COLOR_ENTER
                        },
                        16f,
                    )
                },
            )
        }
    }

    private fun buildSuggestionBar(): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(dp(8), dp(6), dp(8), dp(6))
            minimumHeight = dp(SUGGESTION_BAR_MIN_DP)
            visibility = View.GONE
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )
        }
    }

    private fun refreshSuggestions() {
        val bar = suggestionBar ?: return
        val log = voiceLog
        val status = statusLine
        if (isRecording || isProcessingVoice || !log.isNullOrBlank() || !status.isNullOrBlank()) {
            clipboardImageUri = null
            clipboardImageMime = null
            clearClipboardPreviewHost()
            bar.removeAllViews()
            bar.visibility = View.VISIBLE
            bar.minimumHeight = dp(SUGGESTION_BAR_MIN_DP)
            bar.gravity = Gravity.CENTER_VERTICAL
            bar.addView(TextView(this).apply {
                text = when {
                    !log.isNullOrBlank() -> log
                    isRecording -> "🎙️ Recording…"
                    isProcessingVoice -> "⏳ Please wait…"
                    else -> status.orEmpty()
                }
                setTextColor(COLOR_TEXT)
                textSize = 13f
                maxLines = 2
                ellipsize = android.text.TextUtils.TruncateAt.END
                setPadding(dp(8), dp(6), dp(8), dp(6))
            })
            return
        }

        bar.removeAllViews()
        bar.visibility = View.GONE

        val host = clipboardPreviewHost
        if (host == null || toolbar == null) {
            clipboardImageUri = null
            clipboardImageMime = null
            return
        }

        val clip = inspectPrimaryClip()
        val snapshot = ImeClipboardPreview.classify(clip.text, clip.hasImage)
        if (!ImeClipboardPreview.shouldShowChip(
                sensitiveField = sensitiveField,
                recordingOrProcessing = false,
                voiceLog = null,
                snapshot = snapshot,
            )
        ) {
            clipboardImageUri = null
            clipboardImageMime = null
            clearClipboardPreviewHost()
            return
        }

        clipboardImageUri = clip.imageUri
        clipboardImageMime = clip.imageMime
        host.removeAllViews()
        host.visibility = View.VISIBLE
        host.addView(buildClipboardChip(snapshot, clip.thumbnail))
    }

    private fun clearClipboardPreviewHost() {
        val host = clipboardPreviewHost ?: return
        host.removeAllViews()
        host.visibility = View.GONE
    }

    private fun buildClipboardChip(
        snapshot: ImeClipboardPreview.Snapshot,
        thumbnail: Bitmap?,
    ): View {
        val chip = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = rounded(COLOR_TOOL, 12f)
            minimumHeight = dp(36)
            setPadding(dp(9), dp(8), dp(9), dp(8))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                dp(36),
            )
            isClickable = true
            isFocusable = true
        }
        when (snapshot.kind) {
            ImeClipboardPreview.Kind.Text -> {
                chip.addView(TextView(this).apply {
                    text = snapshot.textPreview
                    setTextColor(COLOR_TEXT)
                    textSize = 12f
                    maxLines = 1
                    ellipsize = android.text.TextUtils.TruncateAt.END
                    maxWidth = dp(110)
                })
                chip.setOnClickListener { commitClipboardTextPreview() }
            }
            ImeClipboardPreview.Kind.Image -> {
                if (thumbnail != null) {
                    chip.addView(ImageView(this).apply {
                        setImageBitmap(thumbnail)
                        scaleType = ImageView.ScaleType.CENTER_CROP
                        layoutParams = LinearLayout.LayoutParams(dp(20), dp(20))
                        background = rounded(0xFF555555.toInt(), 4f)
                    })
                } else {
                    chip.addView(TextView(this).apply {
                        text = "🖼️"
                        textSize = 12f
                    })
                }
                chip.setOnClickListener { commitClipboardImage() }
            }
            ImeClipboardPreview.Kind.Empty -> Unit
        }
        return chip
    }

    private fun commitClipboardTextPreview() {
        val text = readPrimaryClipText()
        if (text.isNullOrBlank()) {
            refreshSuggestions()
            return
        }
        currentInputConnection?.commitText(text, 1)
        clipboardStore.add(text)
    }

    private fun commitClipboardImage() {
        val uri = clipboardImageUri
        val mime = clipboardImageMime
        if (uri == null || mime.isNullOrBlank()) {
            Toast.makeText(this, "No image to insert", Toast.LENGTH_SHORT).show()
            return
        }
        if (Build.VERSION.SDK_INT < 25) {
            Toast.makeText(this, "Image insert needs Android 7.1+", Toast.LENGTH_SHORT).show()
            return
        }
        val editorInfo = currentInputEditorInfo
        val supported = editorInfo?.contentMimeTypes.orEmpty().any { advertised ->
            ClipDescription.compareMimeTypes(advertised, mime) ||
                ClipDescription.compareMimeTypes(advertised, "image/*")
        }
        if (!supported) {
            Toast.makeText(this, "This field cannot accept images", Toast.LENGTH_SHORT).show()
            return
        }
        val ic = currentInputConnection ?: return
        val contentInfo = InputContentInfo(uri, ClipDescription("clipboard-image", arrayOf(mime)))
        val ok = runCatching {
            ic.commitContent(contentInfo, InputConnection.INPUT_CONTENT_GRANT_READ_URI_PERMISSION, null)
        }.getOrDefault(false)
        if (!ok) {
            Toast.makeText(this, "Could not insert image", Toast.LENGTH_SHORT).show()
        }
    }

    private fun buildKeyboard(): LinearLayout {
        letterBindings.clear()
        shiftVisual = null
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, dp(2), 0, dp(2))
        }
        val rows = if (layer == Layer.Letters) letterRows() else symbolRows()
        rows.forEach { keys ->
            column.addView(buildKeyRow(keys))
        }
        return column
    }

    private fun letterRows(): List<List<KeySpec>> {
        fun letter(label: String): KeySpec {
            return KeySpec(
                ImeKeyboardLayout.displayLetter(label, lettersUppercase()),
                action = KeyAction.CommitChar(label.first()),
                baseLabel = label,
            )
        }
        val layout = currentLayout()
        val row2 = ImeKeyboardLayout.row2(layout)
        val r1 = ImeKeyboardLayout.row1(layout).map(::letter)
        val r2 = listOf(letter(row2.first()).copy(widthWeight = 1.5f, visualLead = 0.5f)) +
            row2.subList(1, row2.lastIndex).map(::letter) +
            listOf(letter(row2.last()).copy(widthWeight = 1.5f, visualTrail = 0.5f))
        val r3 = listOf(
            KeySpec(if (capsLock) "⇪" else "⇧", widthWeight = 1.5f, action = KeyAction.Shift),
        ) + ImeKeyboardLayout.row3(layout).map(::letter) + listOf(
            KeySpec("⌫", widthWeight = 1.5f, action = KeyAction.Backspace),
        )
        return listOf(r1, r2, r3, bottomRow(lettersLayer = true))
    }

    private fun symbolRows(): List<List<KeySpec>> {
        val r1 = listOf("1", "2", "3", "4", "5", "6", "7", "8", "9", "0").map {
            KeySpec(it, action = KeyAction.CommitChar(it.first()))
        }
        val r2 = listOf("@", "#", "€", "_", "&", "-", "+", "(", ")", "/").map {
            KeySpec(it, action = KeyAction.CommitChar(it.first()))
        }
        val r3 = listOf(
            KeySpec("=", action = KeyAction.CommitChar('=')),
            KeySpec("*", action = KeyAction.CommitChar('*')),
            KeySpec("\"", action = KeyAction.CommitChar('"')),
            KeySpec("'", action = KeyAction.CommitChar('\'')),
            KeySpec(":", action = KeyAction.CommitChar(':')),
            KeySpec(";", action = KeyAction.CommitChar(';')),
            KeySpec("!", action = KeyAction.CommitChar('!')),
            KeySpec("?", action = KeyAction.CommitChar('?')),
            KeySpec("⌫", widthWeight = 1.5f, action = KeyAction.Backspace),
        )
        return listOf(r1, r2, r3, bottomRow(lettersLayer = false))
    }

    private fun bottomRow(lettersLayer: Boolean): List<KeySpec> {
        return listOf(
            KeySpec(
                if (lettersLayer) "?123" else "ABC",
                widthWeight = 1.4f,
                action = if (lettersLayer) KeyAction.Symbols else KeyAction.Letters,
            ),
            KeySpec(",", widthWeight = 1f, action = KeyAction.CommitChar(',')),
            KeySpec("☺", widthWeight = 1.05f, action = KeyAction.Emoji),
            KeySpec(ImeKeyboardLayout.spaceLabel(currentLayout()), widthWeight = 4.1f, action = KeyAction.Space),
            KeySpec(".", widthWeight = 1f, action = KeyAction.CommitChar('.')),
            KeySpec("⏎", widthWeight = 1.4f, action = KeyAction.Enter, accent = true),
        )
    }

    private fun currentLayout(): String = activeLayout

    private fun buildKeyRow(keys: List<KeySpec>): LinearLayout {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            clipChildren = false
            clipToPadding = false
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(66),
            )
        }
        keys.forEach { key ->
            row.addView(buildKeyCell(key))
        }
        return row
    }

    private fun buildKeyCell(key: KeySpec): View {
        val normalColor = when {
            key.accent -> COLOR_ENTER
            key.action == KeyAction.Shift && capsLock -> 0xFF3D6BFF.toInt()
            key.action == KeyAction.Shift && (shiftOnce || autoCapNext) -> 0xFF5C5C5E.toInt()
            else -> COLOR_KEY
        }
        val visual = TextView(this).apply {
            text = key.label
            textSize = when {
                key.label.length > 3 -> 13f
                key.label.length > 1 -> 15f
                else -> 20f
            }
            gravity = Gravity.CENTER
            includeFontPadding = false
            setPadding(0, 0, 0, 0)
            isAllCaps = false
            setTextColor(COLOR_TEXT)
            background = InsetDrawable(
                keyBackground(normalColor, 16f),
                dp(2),
                dp(3),
                dp(2),
                dp(3),
            )
            isClickable = false
            isFocusable = false
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        if (key.baseLabel.length == 1 && key.baseLabel.first().isLetter()) {
            letterBindings.add(LetterBinding(key.baseLabel, visual))
        }
        if (key.action == KeyAction.Shift) {
            shiftVisual = visual
        }
        val holdAction = key.action == KeyAction.Shift || ImeAccentHold.hasHold(key.baseLabel)
        val cell = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, key.widthWeight)
            isClickable = true
            isFocusable = true
            isSoundEffectsEnabled = false
            if (key.action == KeyAction.Backspace) {
                setOnTouchListener { _, event ->
                    when (event.actionMasked) {
                        MotionEvent.ACTION_DOWN -> {
                            visual.isPressed = true
                            keyFeedback(visual)
                            backspaceOriginX = event.rawX
                            backspaceSwipeWords = 0
                            deleteBackward()
                            startBackspaceRepeat()
                            true
                        }
                        MotionEvent.ACTION_MOVE -> {
                            val extra = ImeBackspaceGestures.extraWordsFromSwipe(
                                event.rawX - backspaceOriginX,
                                dp(ImeBackspaceGestures.WORD_SLOT_DP).toFloat(),
                            )
                            if (extra > backspaceSwipeWords) {
                                stopBackspaceRepeat()
                                repeat(extra - backspaceSwipeWords) { deleteWord() }
                                backspaceSwipeWords = extra
                            }
                            true
                        }
                        MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                            visual.isPressed = false
                            stopBackspaceRepeat()
                            true
                        }
                        else -> true
                    }
                }
            } else {
                setOnTouchListener { _, event ->
                    val isSpace = key.action == KeyAction.Space
                    when (event.actionMasked) {
                        MotionEvent.ACTION_DOWN -> {
                            visual.isPressed = true
                            keyFeedback(visual)
                            longPressFired = false
                            spaceCursorArmed = false
                            accentHoldOriginX = event.rawX
                            spaceOriginX = event.rawX
                            spaceOriginY = event.rawY
                            pendingKey = key
                            pendingKeyVisual = visual
                            when {
                                isSpace -> mainHandler.postDelayed(
                                    spaceCursorRunnable,
                                    ImeSpaceGestures.HOLD_MS,
                                )
                                holdAction -> mainHandler.postDelayed(longPressRunnable, KEY_HOLD_MS)
                                else -> onKey(key.action)
                            }
                            true
                        }
                        MotionEvent.ACTION_MOVE -> {
                            when {
                                spaceCursorArmed -> updateSpaceCursor(event.rawX, event.rawY)
                                longPressFired && accentPopup != null -> updateAccentHoldFromMove(event.rawX)
                            }
                            true
                        }
                        MotionEvent.ACTION_UP -> {
                            visual.isPressed = false
                            mainHandler.removeCallbacks(longPressRunnable)
                            mainHandler.removeCallbacks(spaceCursorRunnable)
                            when {
                                spaceCursorArmed -> {
                                    spaceCursorArmed = false
                                    dismissSpaceLoupe()
                                }
                                isSpace -> commitSpace()
                                holdAction && !longPressFired -> onKey(key.action)
                                longPressFired && accentPopup != null -> commitAccentHold()
                            }
                            pendingKey = null
                            pendingKeyVisual = null
                            true
                        }
                        MotionEvent.ACTION_CANCEL -> {
                            visual.isPressed = false
                            cancelPendingKey()
                            dismissAccents()
                            spaceCursorArmed = false
                            dismissSpaceLoupe()
                            true
                        }
                        else -> true
                    }
                }
            }
        }
        if (key.visualLead > 0f) {
            cell.addView(View(this).apply {
                layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, key.visualLead)
            })
        }
        val visualWeight = (key.widthWeight - key.visualLead - key.visualTrail).coerceAtLeast(0.1f)
        cell.addView(visual, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, visualWeight))
        if (key.visualTrail > 0f) {
            cell.addView(View(this).apply {
                layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, key.visualTrail)
            })
        }
        return cell
    }

    private fun onKey(action: KeyAction) {
        val ic = currentInputConnection ?: return
        when (action) {
            is KeyAction.CommitChar -> {
                val raw = action.value.toString()
                val isLetter = raw.first().isLetter()
                val text = if (isLetter) applyCapitalization(raw) else raw
                ic.commitText(text, 1)
                if (isLetter) {
                    composing.append(text)
                    consumeOneShotShift()
                    if (!isRecording && !isProcessingVoice) voiceLog = null
                } else {
                    composing.clear()
                    if (text == "." || text == "!" || text == "?") {
                        armAutoCap()
                    }
                }
                if (layer == Layer.Symbols && !text.first().isDigit()) {
                    layer = Layer.Letters
                    renderContent()
                    return
                }
                if (isLetter || text == "." || text == "!" || text == "?") {
                    applyLetterCase()
                    return
                }
            }
            KeyAction.Space -> commitSpace()
            KeyAction.Backspace -> deleteBackward()
            KeyAction.Enter -> {
                val info = currentInputEditorInfo
                val inputType = info?.inputType ?: 0
                val imeOptions = info?.imeOptions ?: 0
                when (ImeEnterBehavior.decide(inputType, imeOptions)) {
                    ImeEnterBehavior.Outcome.Newline -> {
                        ic.commitText("\n", 1)
                        armAutoCap()
                        applyLetterCase()
                    }
                    ImeEnterBehavior.Outcome.EditorAction -> {
                        ic.performEditorAction(ImeEnterBehavior.actionId(imeOptions))
                    }
                    ImeEnterBehavior.Outcome.SendEnterKey -> {
                        ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER))
                        ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER))
                    }
                }
                composing.clear()
            }
            KeyAction.Shift -> {
                val next = ImeShiftState(capsLock, shiftOnce, autoCapNext).tap()
                capsLock = next.capsLock
                shiftOnce = next.shiftOnce
                autoCapNext = next.autoCapNext
                applyLetterCase()
                return
            }
            KeyAction.Symbols -> {
                layer = Layer.Symbols
                shiftOnce = false
                capsLock = false
                renderContent()
                return
            }
            KeyAction.Letters -> {
                layer = Layer.Letters
                renderContent()
                return
            }
            KeyAction.Emoji -> {
                openSheet(ImeSheetKind.Emoji)
                return
            }
        }
        refreshSuggestions()
    }

    private fun keyFeedback(view: View) {
        if (config?.hapticFeedbackEnabled != false) {
            view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
        }
        if (config?.soundFeedbackEnabled != false) {
            playKeyClick()
        }
    }

    private fun ensureKeyClick() {
        if (keySoundPool != null) return
        val pool = SoundPool.Builder()
            .setMaxStreams(4)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            .build()
        pool.setOnLoadCompleteListener { _, sampleId, status ->
            if (status == 0 && sampleId == keyClickId) keyClickReady = true
        }
        keyClickId = pool.load(this, R.raw.ime_key_click, 1)
        keySoundPool = pool
    }

    private fun playKeyClick() {
        ensureKeyClick()
        if (!keyClickReady) return
        keySoundPool?.play(keyClickId, 0.4f, 0.4f, 1, 0, 1f)
    }

    private fun haptic() {
        keyFeedback(root ?: return)
    }

    private fun startBackspaceRepeat() {
        backspaceHeld = true
        mainHandler.removeCallbacks(backspaceRepeatRunnable)
        mainHandler.postDelayed(backspaceRepeatRunnable, 400)
    }

    private fun stopBackspaceRepeat() {
        backspaceHeld = false
        mainHandler.removeCallbacks(backspaceRepeatRunnable)
    }

    private fun commitSpace() {
        val ic = currentInputConnection ?: return
        val before = ic.getTextBeforeCursor(MAX_SOURCE_CHARS, 0)?.toString().orEmpty()
        composing.clear()
        if (ImeSpaceGestures.shouldInsertPeriod(before)) {
            if (!ic.deleteSurroundingText(1, 0)) {
                sendDeleteKey(ic)
            }
            ic.commitText(". ", 1)
            armAutoCap()
            applyLetterCase()
        } else {
            ic.commitText(" ", 1)
        }
        refreshSuggestions()
    }

    private fun updateSpaceCursor(rawX: Float, rawY: Float) {
        val ic = currentInputConnection ?: return
        val charSteps = ImeSpaceGestures.cursorSteps(
            rawX - spaceOriginX,
            dp(ImeSpaceGestures.CURSOR_SLOT_DP).toFloat(),
        )
        val lineSteps = ImeSpaceGestures.cursorSteps(
            rawY - spaceOriginY,
            dp(ImeSpaceGestures.LINE_SLOT_DP).toFloat(),
        )
        if (charSteps == lastCharSteps && lineSteps == lastLineSteps) return
        lastCharSteps = charSteps
        lastLineSteps = lineSteps
        val pos = ImeSpaceGestures.moveIndex(spaceSnapshot, spaceCursorBefore, charSteps, lineSteps)
        ic.setSelection(pos, pos)
        updateSpaceLoupe(pos)
    }

    private fun showSpaceLoupe(caretIndex: Int) {
        dismissSpaceLoupe()
        val tv = TextView(this).apply {
            setTextColor(COLOR_TEXT)
            textSize = 22f
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            setPadding(dp(12), dp(8), dp(12), dp(8))
            background = rounded(COLOR_TOOL, 18f)
            elevation = dp(6).toFloat()
        }
        spaceLoupeText = tv
        val popup = PopupWindow(
            tv,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            false,
        ).apply {
            isClippingEnabled = false
            elevation = dp(8).toFloat()
        }
        spaceLoupe = popup
        updateSpaceLoupe(caretIndex)
        val anchor = pendingKeyVisual ?: root ?: return
        runCatching {
            popup.showAtLocation(anchor, Gravity.CENTER_HORIZONTAL or Gravity.TOP, 0, -dp(72))
        }.onFailure {
            runCatching { popup.showAsDropDown(anchor, 0, -dp(56)) }
        }
    }

    private fun updateSpaceLoupe(caretIndex: Int) {
        val snippet = ImeSpaceGestures.loupeSnippet(spaceSnapshot, caretIndex)
        val marker = ImeSpaceGestures.LOUPE_MARKER
        val start = snippet.indexOf(marker)
        val spannable = SpannableString(snippet)
        if (start >= 0) {
            spannable.setSpan(
                ForegroundColorSpan(COLOR_ENTER),
                start,
                start + 1,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
            )
        }
        spaceLoupeText?.text = spannable
    }

    private fun dismissSpaceLoupe() {
        runCatching { spaceLoupe?.dismiss() }
        spaceLoupe = null
        spaceLoupeText = null
    }

    private fun deleteWord() {
        val ic = currentInputConnection ?: return
        ic.finishComposingText()
        composing.clear()
        val before = ic.getTextBeforeCursor(MAX_SOURCE_CHARS, 0)?.toString().orEmpty()
        val count = ImeBackspaceGestures.wordDeleteCount(before)
        if (count <= 0) return
        if (!ic.deleteSurroundingText(count, 0)) {
            repeat(count) { sendDeleteKey(ic) }
        }
        refreshAutoCapFromField()
    }

    private fun deleteBackward() {
        val ic = currentInputConnection ?: return
        ic.finishComposingText()
        composing.clear()
        if (ic.getSelectedText(0).isNullOrEmpty()) {
            if (!ic.deleteSurroundingText(1, 0)) {
                sendDeleteKey(ic)
            }
        } else {
            ic.commitText("", 1)
        }
        refreshAutoCapFromField()
    }

    private fun refreshAutoCapFromField() {
        if (capsLock) {
            applyLetterCase()
            return
        }
        if (config?.autoCapitalizeEnabled == false) {
            autoCapNext = false
            shiftOnce = false
            applyLetterCase()
            return
        }
        val before = currentInputConnection?.getTextBeforeCursor(128, 0)?.toString().orEmpty()
        autoCapNext = ImeAutoCap.shouldCapitalize(before)
        shiftOnce = false
        applyLetterCase()
    }

    private fun sendDeleteKey(ic: android.view.inputmethod.InputConnection) {
        ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DEL))
        ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_DEL))
    }

    private fun setStatus(text: String?, clearAfterMs: Long = 0L) {
        statusLine = text
        refreshSuggestions()
        if (!text.isNullOrBlank() && clearAfterMs > 0L) {
            mainHandler.postDelayed({
                if (statusLine == text) {
                    statusLine = null
                    refreshSuggestions()
                }
            }, clearAfterMs)
        }
    }

    private fun runGrammarInPlace() {
        if (sensitiveField) return
        if (aiBusy || isRecording || isProcessingVoice) return
        val cfg = config
        if (cfg == null || !cfg.hasUsableProvider()) {
            setStatus("❌ Open EchoScribe settings", 2500)
            return
        }
        val chip = ImeAiActions.grammarChips(cfg).firstOrNull { it.id == "grammar_fix" }
        val source = readSourceText()
        if (source.isBlank()) {
            setStatus("❌ Kein Text im Feld", 2000)
            return
        }
        val instruction = chip?.prompt.orEmpty()
        if (instruction.isBlank()) {
            setStatus("❌ Please choose an option", 2000)
            return
        }
        aiBusy = true
        setStatus("⏳ Grammar…")
        Thread {
            try {
                val client = NativeDictationApiClient(cfg)
                val system = ImeAiActions.systemPromptFor(ImeSheetKind.Grammar)
                val results = client.rewrite(system, "$instruction\n\nText:\n$source", variantCount = 1)
                val out = results.firstOrNull()?.trim().orEmpty()
                mainHandler.post {
                    aiBusy = false
                    if (out.isEmpty()) {
                        setStatus("❌ Leere Antwort", 2500)
                    } else {
                        replaceFieldText(out)
                        setStatus("✅ Eingefügt", 1500)
                    }
                }
            } catch (e: Exception) {
                mainHandler.post {
                    aiBusy = false
                    setStatus("❌ " + (e.message?.take(80) ?: "AI failed"), 2500)
                }
            }
        }.start()
    }

    private fun openSheet(kind: ImeSheetKind, autoRun: Boolean = ImeAiActions.shouldAutoRunOnToolbarTap(kind)) {
        if (sensitiveField) return
        activeSheet = kind
        selectedChipId = null
        aiResults = emptyList()
        selectedResultIndex = 0
        aiBusy = false
        aiError = null
        italicPrompt = null
        when (kind) {
            ImeSheetKind.Grammar -> selectedChipId = ImeAiActions.grammarChips(config).firstOrNull()?.id
            ImeSheetKind.Tone -> selectedChipId = ImeAiActions.toneChips(config).firstOrNull()?.id
            ImeSheetKind.Translate -> translateTargetCode = "en"
            else -> Unit
        }
        rebuildUi()
        if (autoRun && kind in setOf(ImeSheetKind.Grammar, ImeSheetKind.Tone, ImeSheetKind.Translate)) {
            runAi(kind)
        }
    }

    private fun closeSheetWithoutReplace() {
        activeSheet = null
        aiResults = emptyList()
        aiError = null
        aiBusy = false
        rebuildUi()
    }

    private fun buildAiSheet(kind: ImeSheetKind): View {
        val wrap = FrameLayout(this)
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(8), dp(6), dp(8), dp(8))
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            )
        }

        column.addView(buildSheetChrome(ImeAiActions.sheetTitle(kind), kind))

        val chips = ImeAiActions.chipsFor(kind, config)
        if (chips.isNotEmpty()) {
            column.addView(buildChipRow(chips) { chip ->
                selectedChipId = chip.id
                italicPrompt = chip.prompt
                runAi(kind)
            })
        }

        val selected = chips.firstOrNull { it.id == selectedChipId }
        val clipboardHint = ImeAiActions.clipboardHint(selected)
        if (clipboardHint != null) {
            column.addView(TextView(this).apply {
                text = clipboardHint
                setTextColor(0xFFFFCC80.toInt())
                textSize = 12f
                setPadding(dp(8), dp(8), dp(8), dp(8))
                background = rounded(0xFF3A2F1E.toInt(), 10f)
            })
        } else if (!italicPrompt.isNullOrBlank() || selected != null) {
            column.addView(TextView(this).apply {
                text = italicPrompt ?: selected?.prompt.orEmpty()
                setTextColor(0xFFB0B0B0.toInt())
                textSize = 12f
                setTypeface(typeface, Typeface.ITALIC)
                setPadding(dp(4), dp(6), dp(4), dp(4))
            })
        }

        if (kind == ImeSheetKind.Translate) {
            column.addView(buildLanguagePicker())
        }

        val scroll = ScrollView(this).apply {
            overScrollMode = View.OVER_SCROLL_NEVER
            isNestedScrollingEnabled = false
            descendantFocusability = ViewGroup.FOCUS_BLOCK_DESCENDANTS
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f,
            )
        }
        val resultsCol = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, dp(6), 0, dp(6))
        }
        if (aiBusy) {
            resultsCol.addView(ProgressBar(this).apply {
                layoutParams = LinearLayout.LayoutParams(dp(36), dp(36)).apply {
                    gravity = Gravity.CENTER_HORIZONTAL
                    topMargin = dp(12)
                }
            })
        } else if (!aiError.isNullOrBlank()) {
            resultsCol.addView(TextView(this).apply {
                text = aiError
                setTextColor(0xFFFF8A80.toInt())
                textSize = 13f
                setPadding(dp(8), dp(8), dp(8), dp(8))
            })
        } else if (aiResults.isEmpty()) {
            resultsCol.addView(TextView(this).apply {
                text = if (aiBusy) "Generating…" else "Choose an action"
                setTextColor(0xFF9E9E9E.toInt())
                textSize = 13f
                setPadding(dp(8), dp(12), dp(8), dp(8))
            })
        } else {
            aiResults.forEachIndexed { index, result ->
                resultsCol.addView(TextView(this).apply {
                    text = result
                    setTextColor(COLOR_TEXT)
                    textSize = 14f
                    setPadding(dp(12), dp(10), dp(12), dp(10))
                    isFocusable = false
                    isFocusableInTouchMode = false
                    setTextIsSelectable(false)
                    movementMethod = null
                    background = rounded(
                        if (index == selectedResultIndex) 0xFF2F5D4A.toInt() else COLOR_KEY,
                        10f,
                    )
                    layoutParams = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                    ).apply { bottomMargin = dp(8) }
                    setOnClickListener {
                        selectedResultIndex = index
                        for (i in 0 until resultsCol.childCount) {
                            val child = resultsCol.getChildAt(i)
                            if (child is TextView) {
                                child.background = rounded(
                                    if (i == selectedResultIndex) 0xFF2F5D4A.toInt() else COLOR_KEY,
                                    10f,
                                )
                            }
                        }
                    }
                })
            }
        }
        scroll.addView(resultsCol)
        column.addView(scroll)

        column.addView(buildSheetActionRow())

        wrap.addView(column)
        wrap.layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT,
        )
        wrap.minimumHeight = dp(320)
        return wrap
    }

    private fun buildSheetActionRow(): LinearLayout {
        fun actionButton(
            label: String,
            fill: Int,
            weight: Float,
            enabled: Boolean,
            onClick: () -> Unit,
        ): Button {
            return Button(this).apply {
                text = label
                isAllCaps = false
                isEnabled = enabled
                minWidth = 0
                minimumWidth = 0
                minHeight = 0
                minimumHeight = 0
                stateListAnimator = null
                elevation = 0f
                setPadding(0, 0, 0, 0)
                setTextColor(COLOR_TEXT)
                textSize = 15f
                background = rounded(fill, 14f)
                layoutParams = LinearLayout.LayoutParams(0, dp(48), weight)
                setOnClickListener { onClick() }
            }
        }
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(
                actionButton(
                    if (selectedChipUsesClipboard()) "Insert reply" else "Replace text",
                    COLOR_ENTER,
                    4f,
                    aiResults.isNotEmpty() && !aiBusy,
                ) { replaceWithSelectedResult() },
            )
            addView(View(this@EchoScribeImeService).apply {
                layoutParams = LinearLayout.LayoutParams(dp(4), dp(28)).apply {
                    gravity = Gravity.CENTER_VERTICAL
                    marginStart = dp(4)
                    marginEnd = dp(4)
                }
                background = rounded(0x66FFFFFF.toInt(), 2f)
            })
            addView(
                actionButton("←", COLOR_TOOL, 1f, true) { closeSheetWithoutReplace() }.apply {
                    contentDescription = "Back to keyboard"
                    textSize = 20f
                },
            )
        }
    }

    private fun buildSheetChrome(title: String, kind: ImeSheetKind): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(Button(this@EchoScribeImeService).apply {
                text = "←"
                isAllCaps = false
                setTextColor(COLOR_TEXT)
                background = rounded(COLOR_KEY, 8f)
                layoutParams = LinearLayout.LayoutParams(dp(44), dp(40))
                setOnClickListener { closeSheetWithoutReplace() }
            })
            addView(TextView(this@EchoScribeImeService).apply {
                text = title
                setTextColor(COLOR_TEXT)
                textSize = 16f
                setTypeface(typeface, Typeface.BOLD)
                setPadding(dp(10), 0, dp(10), 0)
                layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            })
            val langLabel = if (kind == ImeSheetKind.Translate) {
                ImeLanguages.labelFor(translateTargetCode)
            } else {
                "German-DE"
            }
            addView(TextView(this@EchoScribeImeService).apply {
                text = langLabel
                setTextColor(COLOR_TEXT)
                textSize = 12f
                setPadding(dp(10), dp(6), dp(10), dp(6))
                background = rounded(COLOR_KEY, 14f)
                setOnClickListener {
                    if (kind == ImeSheetKind.Translate) {
                        cycleTranslateLanguage()
                    }
                }
            })
            addView(space(6))
            addView(Button(this@EchoScribeImeService).apply {
                text = "↻"
                isAllCaps = false
                setTextColor(COLOR_TEXT)
                background = rounded(COLOR_KEY, 8f)
                layoutParams = LinearLayout.LayoutParams(dp(44), dp(40))
                isEnabled = !aiBusy
                setOnClickListener { runAi(kind) }
            })
        }
    }

    private fun buildChipRow(chips: List<ImeChip>, onSelect: (ImeChip) -> Unit): HorizontalScrollView {
        val scroll = HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            overScrollMode = View.OVER_SCROLL_NEVER
            isNestedScrollingEnabled = false
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = dp(8) }
        }
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(2), 0, dp(2), 0)
        }
        chips.forEach { chip ->
            val selected = chip.id == selectedChipId
            row.addView(TextView(this).apply {
                text = chip.label
                setTextColor(COLOR_TEXT)
                textSize = 12f
                setPadding(dp(12), dp(8), dp(12), dp(8))
                background = rounded(if (selected) COLOR_SELECTED else COLOR_KEY, 16f)
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ).apply { marginEnd = dp(6) }
                setOnClickListener { onSelect(chip) }
            })
        }
        scroll.addView(row)
        return scroll
    }

    private fun buildLanguagePicker(): HorizontalScrollView {
        val scroll = HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = dp(6) }
        }
        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        ImeLanguages.translateTargets.forEach { lang ->
            val selected = lang.code == translateTargetCode
            row.addView(TextView(this).apply {
                text = lang.label
                setTextColor(COLOR_TEXT)
                textSize = 12f
                setPadding(dp(10), dp(7), dp(10), dp(7))
                background = rounded(if (selected) COLOR_SELECTED else COLOR_KEY, 14f)
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ).apply { marginEnd = dp(6) }
                setOnClickListener {
                    translateTargetCode = lang.code
                    renderContent()
                }
            })
        }
        scroll.addView(row)
        return scroll
    }

    private fun cycleTranslateLanguage() {
        val list = ImeLanguages.translateTargets
        val idx = list.indexOfFirst { it.code == translateTargetCode }
        translateTargetCode = list[(idx + 1).floorMod(list.size)].code
        runAi(ImeSheetKind.Translate)
    }

    private fun runAi(kind: ImeSheetKind) {
        if (sensitiveField) return
        val cfg = config
        if (cfg == null || !cfg.hasUsableProvider()) {
            aiError = "Open EchoScribe settings and configure a provider"
            renderContent()
            return
        }
        val chip = ImeAiActions.chipsFor(kind, cfg).firstOrNull { it.id == selectedChipId }
        val source = if (chip?.usesClipboard == true) {
            readPrimaryClipText().orEmpty()
        } else {
            readSourceText()
        }
        if (source.isBlank()) {
            aiError = if (chip?.usesClipboard == true) {
                "Clipboard is empty. Copy the message, then tap ↻."
            } else {
                "Kein Text im Feld"
            }
            renderContent()
            return
        }

        val instruction = when (kind) {
            ImeSheetKind.Translate -> ImeAiActions.translatePrompt(ImeLanguages.labelFor(translateTargetCode))
            else -> chip?.prompt.orEmpty()
        }
        if (instruction.isBlank()) {
            aiError = "Please choose an option"
            renderContent()
            return
        }

        val variantCount = if (kind == ImeSheetKind.Tone) 3 else 1
        aiBusy = true
        aiError = null
        aiResults = emptyList()
        renderContent()

        Thread {
            try {
                val client = NativeDictationApiClient(cfg)
                val system = ImeAiActions.systemPromptFor(kind)
                val user = "$instruction\n\nText:\n$source"
                val results = client.rewrite(system, user, variantCount = variantCount)
                mainHandler.post {
                    aiBusy = false
                    if (results.isEmpty()) {
                        aiError = "Leere Antwort"
                    } else {
                        aiResults = results
                        selectedResultIndex = 0
                    }
                    renderContent()
                }
            } catch (e: Exception) {
                mainHandler.post {
                    aiBusy = false
                    aiError = e.message?.take(160) ?: "AI request failed"
                    renderContent()
                }
            }
        }.start()
    }

    private fun replaceWithSelectedResult() {
        val text = aiResults.getOrNull(selectedResultIndex)?.trim().orEmpty()
        if (text.isEmpty()) return
        if (selectedChipUsesClipboard()) {
            currentInputConnection?.commitText(text, 1)
        } else {
            replaceFieldText(text)
        }
        closeSheetWithoutReplace()
    }

    private fun selectedChipUsesClipboard(): Boolean {
        val kind = activeSheet ?: return false
        return ImeAiActions.chipsFor(kind, config).firstOrNull { it.id == selectedChipId }?.usesClipboard == true
    }

    private fun replaceFieldText(text: String) {
        val ic = currentInputConnection ?: return
        val extracted = ic.getExtractedText(ExtractedTextRequest(), 0)
        if (extracted != null) {
            val full = extracted.text?.toString().orEmpty()
            val start = extracted.selectionStart.coerceAtLeast(0)
            val end = extracted.selectionEnd.coerceAtLeast(start)
            if (end > start) {
                ic.setSelection(start, end)
                ic.commitText(text, 1)
                return
            }
            if (full.isNotEmpty()) {
                ic.finishComposingText()
                ic.performContextMenuAction(android.R.id.selectAll)
                ic.commitText(text, 1)
                return
            }
        }
        val beforeLen = ic.getTextBeforeCursor(MAX_SOURCE_CHARS, 0)?.length ?: 0
        val afterLen = ic.getTextAfterCursor(MAX_SOURCE_CHARS, 0)?.length ?: 0
        if (beforeLen > 0 || afterLen > 0) {
            ic.deleteSurroundingText(beforeLen, afterLen)
        }
        ic.commitText(text, 1)
    }

    private fun readSourceText(): String {
        val ic = currentInputConnection ?: return ""
        val extracted = ic.getExtractedText(ExtractedTextRequest(), 0)
        if (extracted != null) {
            val full = extracted.text?.toString().orEmpty()
            val start = extracted.selectionStart
            val end = extracted.selectionEnd
            if (start >= 0 && end > start && end <= full.length) {
                return full.substring(start, end).take(MAX_SOURCE_CHARS)
            }
            if (full.isNotBlank()) return full.take(MAX_SOURCE_CHARS)
        }
        val before = ic.getTextBeforeCursor(MAX_SOURCE_CHARS, 0)?.toString().orEmpty()
        val after = ic.getTextAfterCursor(MAX_SOURCE_CHARS, 0)?.toString().orEmpty()
        return (before + after).take(MAX_SOURCE_CHARS)
    }

    private fun buildEmojiPanel(): LinearLayout {
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(8), dp(8), dp(8), dp(8))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(360),
            )
        }
        column.addView(buildSimpleHeader("Emoji") { closeSheetWithoutReplace() })
        val body = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        val recents = recentEmojiStore.load()
        if (recents.isNotEmpty()) {
            body.addView(emojiSectionLabel("Zuletzt verwendet"))
            addEmojiRows(body, recents.take(16))
        }
        ImeEmojiCatalog.categories.forEach { category ->
            body.addView(emojiSectionLabel(category.title))
            addEmojiRows(body, category.emojis)
        }
        val scroll = ScrollView(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f,
            )
            isFillViewport = true
            addView(body)
        }
        column.addView(scroll)
        return column
    }

    private fun emojiSectionLabel(title: String): TextView {
        return TextView(this).apply {
            text = title
            setTextColor(0xFF9E9E9E.toInt())
            textSize = 12f
            setPadding(dp(4), dp(8), dp(4), dp(4))
        }
    }

    private fun addEmojiRows(column: LinearLayout, emojis: List<String>) {
        emojis.chunked(8).forEach { rowEmojis ->
            val row = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    dp(44),
                )
            }
            rowEmojis.forEach { emoji ->
                row.addView(TextView(this).apply {
                    text = emoji
                    textSize = 20f
                    gravity = Gravity.CENTER
                    background = rounded(COLOR_KEY, 8f)
                    layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1f).apply {
                        setMargins(dp(2), dp(2), dp(2), dp(2))
                    }
                    setOnClickListener { commitEmoji(emoji) }
                })
            }
            column.addView(row)
        }
    }

    private fun commitEmoji(emoji: String) {
        currentInputConnection?.commitText(emoji, 1)
        recentEmojiStore.add(emoji)
        if (activeSheet == ImeSheetKind.Emoji) renderContent()
    }

    private fun buildClipboardPanel(): LinearLayout {
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(8), dp(8), dp(8), dp(8))
        }
        column.addView(buildSimpleHeader("Clipboard") { closeSheetWithoutReplace() })
        column.addView(TextView(this).apply {
            text = "Stored on this device · History · Tap to insert"
            setTextColor(0xFF9E9E9E.toInt())
            textSize = 11f
            setPadding(dp(4), dp(4), dp(4), dp(8))
        })
        val items = clipboardStore.load()
        val scroll = ScrollView(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f,
            )
        }
        val list = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        if (items.isEmpty()) {
            list.addView(TextView(this).apply {
                text = "No entries yet. Copied text appears here."
                setTextColor(0xFFBDBDBD.toInt())
                setPadding(dp(8), dp(12), dp(8), dp(8))
            })
        } else {
            items.forEach { item ->
                list.addView(TextView(this).apply {
                    text = item
                    maxLines = 3
                    setTextColor(COLOR_TEXT)
                    textSize = 13f
                    setPadding(dp(12), dp(10), dp(12), dp(10))
                    background = rounded(COLOR_KEY, 8f)
                    layoutParams = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                    ).apply { bottomMargin = dp(6) }
                    setOnClickListener {
                        currentInputConnection?.commitText(item, 1)
                        closeSheetWithoutReplace()
                    }
                })
            }
        }
        scroll.addView(list)
        column.addView(scroll)
        return column
    }

    private fun buildMorePanel(): LinearLayout {
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(8), dp(8), dp(8), dp(8))
        }
        column.addView(buildSimpleHeader("More") { closeSheetWithoutReplace() })
        column.addView(TextView(this).apply {
            text = "More options coming later. Find settings in the EchoScribe app under Keyboard."
            setTextColor(COLOR_TEXT)
            textSize = 13f
            setPadding(dp(8), dp(16), dp(8), dp(8))
        })
        return column
    }

    private fun buildSimpleHeader(title: String, onBack: () -> Unit): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(Button(this@EchoScribeImeService).apply {
                text = "←"
                isAllCaps = false
                setTextColor(COLOR_TEXT)
                background = rounded(COLOR_KEY, 8f)
                layoutParams = LinearLayout.LayoutParams(dp(44), dp(40))
                setOnClickListener { onBack() }
            })
            addView(TextView(this@EchoScribeImeService).apply {
                text = title
                setTextColor(COLOR_TEXT)
                textSize = 16f
                setTypeface(typeface, Typeface.BOLD)
                setPadding(dp(10), 0, 0, 0)
            })
        }
    }

    private fun onMicTapped() {
        if (sensitiveField) return
        val mode = config?.voiceMode ?: NativeDictationConfigStore(this).loadVoiceMode()
        if (mode == "google") {
            switchToGoogleVoiceIme()
            return
        }
        if (isProcessingVoice) return
        if (isRecording) {
            stopAndTranscribe()
        } else {
            startEchoScribeRecording()
        }
    }

    private fun switchToGoogleVoiceIme() {
        val imm = getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager
        val target = resolveGoogleVoiceImeId(imm)
        if (target == null) {
            Toast.makeText(
                this,
                "Google Voice IME not found. Please install the Google app / voice typing.",
                Toast.LENGTH_LONG,
            ).show()
            return
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                switchInputMethod(target)
            } else {
                @Suppress("DEPRECATION")
                window?.window?.attributes?.token?.let { token ->
                    imm.setInputMethod(token, target)
                } ?: Toast.makeText(this, "Google Voice konnte nicht gewechselt werden", Toast.LENGTH_LONG).show()
            }
        } catch (e: Exception) {
            Toast.makeText(this, e.message ?: "Could not switch to Google Voice", Toast.LENGTH_LONG).show()
        }
    }

    private fun resolveGoogleVoiceImeId(imm: InputMethodManager): String? {
        val preferred = "com.google.android.googlequicksearchbox/com.google.android.voicesearch.ime.VoiceInputMethodService"
        val list = imm.inputMethodList.orEmpty()
        list.firstOrNull { it.id.equals(preferred, ignoreCase = true) }?.id?.let { return it }
        list.firstOrNull { ime ->
            val id = ime.id.lowercase()
            id.contains("voicesearch") || id.contains("voiceinputmethod") ||
                (id.contains("googlequicksearchbox") && id.contains("voice"))
        }?.id?.let { return it }
        return null
    }

    private fun startEchoScribeRecording() {
        val cfg = config
        if (cfg == null || !cfg.isReadyForDictation()) {
            Toast.makeText(this, "EchoScribe STT nicht konfiguriert", Toast.LENGTH_LONG).show()
            return
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            Toast.makeText(this, "Mikrofon-Berechtigung fehlt (in der App erteilen)", Toast.LENGTH_LONG).show()
            return
        }
        try {
            recordingFile = File(cacheDir, "ime_dictation_${System.currentTimeMillis()}.m4a")
            if (cfg.provider == "localAi") {
                Thread {
                    try {
                        NativeDictationApiClient(cfg).preflightLocalAi()
                        mainHandler.post { startRecorderNow() }
                    } catch (e: Exception) {
                        mainHandler.post {
                            Toast.makeText(this, e.message ?: "Local AI nicht erreichbar", Toast.LENGTH_LONG).show()
                            rebuildUi()
                        }
                    }
                }.start()
                return
            }
            startRecorderNow()
        } catch (e: Exception) {
            stopRecordingSilently()
            Toast.makeText(this, e.message ?: "Recording failed", Toast.LENGTH_LONG).show()
        }
    }

    private fun startRecorderNow() {
        try {
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
            isRecording = true
            setVoiceLog("🎙️ Recording… tap mic again to stop")
            rebuildUi()
        } catch (e: Exception) {
            stopRecordingSilently()
            Toast.makeText(this, e.message ?: "Recording failed", Toast.LENGTH_LONG).show()
        }
    }

    private fun stopAndTranscribe() {
        val file = recordingFile
        stopRecordingSilently()
        if (file == null || !file.exists() || file.length() == 0L) {
            Toast.makeText(this, "Recording failed", Toast.LENGTH_SHORT).show()
            rebuildUi()
            return
        }
        val cfg = config
        if (cfg == null || !cfg.isReadyForDictation()) {
            Toast.makeText(this, "Open EchoScribe settings", Toast.LENGTH_LONG).show()
            rebuildUi()
            return
        }
        isProcessingVoice = true
        setVoiceLog("🎙️ Uploading recording…")
        rebuildUi()
        Thread {
            try {
                val client = NativeDictationApiClient(cfg)
                mainHandler.post { setVoiceLog("⏳ Requesting ${voiceModelLabel()}…") }
                val raw = client.transcribe(file)
                mainHandler.post { setVoiceLog("✨ Cleaning up text…") }
                val formatted = client.format(raw)
                mainHandler.post {
                    isProcessingVoice = false
                    if (formatted.isNotBlank()) {
                        copyTranscriptToClipboard(formatted)
                        val inserted = currentInputConnection?.commitText(formatted, 1) == true
                        setVoiceLog(
                            if (inserted) "✅ Inserted · copied to clipboard"
                            else "✅ Copied to clipboard (field no longer active)",
                        )
                    } else {
                        setVoiceLog("⚠️ Empty transcript")
                        Toast.makeText(this, "Empty transcript", Toast.LENGTH_SHORT).show()
                    }
                    rebuildUi()
                }
            } catch (e: Exception) {
                mainHandler.post {
                    isProcessingVoice = false
                    setVoiceLog("⚠️ ${e.message?.take(80) ?: "Transcription failed"}")
                    Toast.makeText(this, e.message?.take(160) ?: "Transcription failed", Toast.LENGTH_LONG).show()
                    rebuildUi()
                }
            } finally {
                runCatching { file.delete() }
            }
        }.start()
    }

    private fun stopRecordingSilently() {
        isRecording = false
        runCatching { recorder?.stop() }
        runCatching { recorder?.reset() }
        runCatching { recorder?.release() }
        recorder = null
    }

    private fun newRecorder(): MediaRecorder {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(this)
        } else {
            @Suppress("DEPRECATION")
            MediaRecorder()
        }
    }

    private fun copyCurrentText() {
        haptic()
        val ic = currentInputConnection
        if (ic == null) {
            setVoiceLog("⚠️ Kein Textfeld aktiv")
            Toast.makeText(this, "Kein Textfeld aktiv", Toast.LENGTH_SHORT).show()
            return
        }
        val selected = ic.getSelectedText(0)?.toString()
        val text = if (!selected.isNullOrBlank()) {
            selected
        } else {
            val extracted = ic.getExtractedText(ExtractedTextRequest(), 0)?.text?.toString()
            if (!extracted.isNullOrBlank()) {
                extracted
            } else {
                val before = ic.getTextBeforeCursor(MAX_SOURCE_CHARS, 0)?.toString().orEmpty()
                val after = ic.getTextAfterCursor(MAX_SOURCE_CHARS, 0)?.toString().orEmpty()
                before + after
            }
        }
        if (text.isBlank()) {
            setVoiceLog("⚠️ Nichts zu kopieren")
            Toast.makeText(this, "Nichts zu kopieren", Toast.LENGTH_SHORT).show()
            return
        }
        val clipboard = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("EchoScribe", text))
        clipboardStore.add(text)
        setVoiceLog("✅ Kopiert")
        Toast.makeText(this, "Kopiert", Toast.LENGTH_SHORT).show()
    }

    private fun pastePrimaryClip() {
        val text = readPrimaryClipText()
        if (text.isNullOrBlank()) {
            openSheet(ImeSheetKind.Clipboard)
            return
        }
        currentInputConnection?.commitText(text, 1)
        clipboardStore.add(text)
    }

    private fun applyCapitalization(raw: String): String {
        return ImeUmlauts.applyCase(raw, lettersUppercase())
    }

    private fun lettersUppercase(): Boolean = capsLock || shiftOnce || autoCapNext

    private fun applyLetterCase() {
        val upper = lettersUppercase()
        letterBindings.forEach { binding ->
            val next = ImeKeyboardLayout.displayLetter(binding.base, upper)
            if (binding.visual.text.toString() != next) {
                binding.visual.text = next
            }
        }
        val shift = shiftVisual ?: return
        shift.text = if (capsLock) "⇪" else "⇧"
        val color = when {
            capsLock -> 0xFF3D6BFF.toInt()
            shiftOnce || autoCapNext -> 0xFF5C5C5E.toInt()
            else -> COLOR_KEY
        }
        shift.background = InsetDrawable(keyBackground(color, 16f), dp(2), dp(3), dp(2), dp(3))
    }

    private fun cancelPendingKey() {
        mainHandler.removeCallbacks(longPressRunnable)
        mainHandler.removeCallbacks(spaceCursorRunnable)
        pendingKey = null
        pendingKeyVisual = null
        longPressFired = false
        spaceCursorArmed = false
        dismissSpaceLoupe()
    }

    private fun consumeOneShotShift() {
        if (capsLock) return
        shiftOnce = false
        autoCapNext = false
    }

    private fun armAutoCap() {
        if (capsLock) return
        autoCapNext = config?.autoCapitalizeEnabled != false
        shiftOnce = false
    }

    private fun resetShiftState(newField: Boolean) {
        if (!capsLock) shiftOnce = false
        autoCapNext = newField && config?.autoCapitalizeEnabled != false
    }

    private fun voiceModelLabel(): String {
        val model = config?.transcriptionModel.orEmpty().lowercase()
        val brand = config?.brandName.orEmpty()
        return when {
            model.contains("3.5-transcribe") -> "Gemini 3.5"
            model.contains("gemini") -> "Gemini"
            model.contains("gpt") || brand.contains("OpenAI", true) -> "OpenAI"
            model.contains("grok") || brand.contains("xAI", true) -> "xAI"
            brand.isNotBlank() -> brand
            else -> "EchoScribe"
        }
    }

    private fun setVoiceLog(message: String?) {
        voiceLog = message
        refreshSuggestions()
    }

    private fun copyTranscriptToClipboard(text: String) {
        val clipboard = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("EchoScribe", text))
        clipboardStore.add(text)
    }

    private fun navigationBottomInset(insets: WindowInsets?): Int {
        val fromSystem = if (insets == null) {
            0
        } else if (Build.VERSION.SDK_INT >= 30) {
            insets.getInsets(WindowInsets.Type.navigationBars()).bottom
        } else {
            @Suppress("DEPRECATION")
            insets.systemWindowInsetBottom
        }
        return maxOf(fromSystem, dp(48))
    }

    private fun showAccentHold(anchor: View, glyphs: List<String>) {
        dismissAccents()
        if (glyphs.isEmpty()) return
        accentHoldGlyphs = glyphs
        accentHoldIndex = ImeAccentHold.defaultIndex()
        val upper = lettersUppercase()
        val views = mutableListOf<TextView>()
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(4), dp(4), dp(4), dp(4))
            background = rounded(0xFF3A3A3C.toInt(), 12f)
        }
        glyphs.forEachIndexed { index, glyph ->
            val cell = TextView(this).apply {
                text = ImeUmlauts.applyCase(glyph, upper)
                setTextColor(COLOR_TEXT)
                textSize = 20f
                setPadding(dp(12), dp(8), dp(12), dp(8))
                background = if (index == accentHoldIndex) {
                    rounded(COLOR_SELECTED, 10f)
                } else {
                    null
                }
            }
            views.add(cell)
            row.addView(cell)
        }
        accentHoldViews = views
        // Non-focusable / non-touchable so ACTION_MOVE keeps going to the key.
        accentPopup = PopupWindow(
            row,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            false,
        ).apply {
            elevation = 12f
            isTouchable = false
            isOutsideTouchable = false
            setBackgroundDrawable(rounded(0xFF3A3A3C.toInt(), 12f))
            showAsDropDown(anchor, 0, -anchor.height - dp(56))
        }
    }

    private fun updateAccentHoldFromMove(rawX: Float) {
        if (accentHoldGlyphs.isEmpty()) return
        val next = ImeAccentHold.indexFromHorizontalDelta(
            deltaPx = rawX - accentHoldOriginX,
            slotWidthPx = dp(ACCENT_SLOT_DP).toFloat(),
            count = accentHoldGlyphs.size,
            startIndex = ImeAccentHold.defaultIndex(),
        )
        if (next == accentHoldIndex) return
        accentHoldIndex = next
        accentHoldViews.forEachIndexed { index, view ->
            view.background = if (index == accentHoldIndex) {
                rounded(COLOR_SELECTED, 10f)
            } else {
                null
            }
        }
    }

    private fun commitAccentHold() {
        val glyph = accentHoldGlyphs.getOrNull(accentHoldIndex)
        dismissAccents()
        if (glyph.isNullOrEmpty()) return
        onKey(KeyAction.CommitChar(glyph.first()))
    }

    private fun dismissAccents() {
        accentPopup?.dismiss()
        accentPopup = null
        accentHoldGlyphs = emptyList()
        accentHoldViews = emptyList()
        accentHoldIndex = 0
    }

    private fun rounded(color: Int, radiusDp: Float): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(color)
            cornerRadius = dp(radiusDp.toInt()).toFloat()
        }
    }

    private fun keyBackground(color: Int, radiusDp: Float): android.graphics.drawable.Drawable {
        if (config?.opticalFeedbackEnabled == false) return rounded(color, radiusDp)
        return StateListDrawable().apply {
            addState(intArrayOf(android.R.attr.state_pressed), rounded(lighten(color), radiusDp))
            addState(intArrayOf(), rounded(color, radiusDp))
        }
    }

    private fun lighten(color: Int): Int {
        val a = color ushr 24
        val r = ((color shr 16) and 0xFF)
        val g = ((color shr 8) and 0xFF)
        val b = color and 0xFF
        return (a shl 24) or
            ((r + ((255 - r) * 0.28f).toInt()) shl 16) or
            ((g + ((255 - g) * 0.28f).toInt()) shl 8) or
            (b + ((255 - b) * 0.28f).toInt())
    }

    private fun space(widthDp: Int): View {
        return View(this).apply {
            layoutParams = LinearLayout.LayoutParams(dp(widthDp), 1)
        }
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }

    private fun Int.floorMod(other: Int): Int {
        val mod = this % other
        return if (mod >= 0) mod else mod + other
    }

    private fun readPrimaryClipText(): String? {
        val clipboard = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
        val clip = clipboard.primaryClip ?: return null
        if (clip.itemCount <= 0) return null
        return clip.getItemAt(0).coerceToText(this)?.toString()?.trim()
    }

    private data class PrimaryClipInspection(
        val text: String?,
        val hasImage: Boolean,
        val imageUri: Uri?,
        val imageMime: String?,
        val thumbnail: Bitmap?,
    )

    private fun inspectPrimaryClip(): PrimaryClipInspection {
        val clipboard = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
        val clip = clipboard.primaryClip
        if (clip == null || clip.itemCount <= 0) {
            return PrimaryClipInspection(
                text = null,
                hasImage = false,
                imageUri = null,
                imageMime = null,
                thumbnail = null,
            )
        }
        val description = clip.description
        val item = clip.getItemAt(0)
        // Prefer explicit text; coerceToText on image URIs often yields the URI string.
        val explicitText = item.text?.toString()?.trim().orEmpty()
        var imageMime: String? = null
        for (i in 0 until description.mimeTypeCount) {
            val mime = description.getMimeType(i)
            if (ClipDescription.compareMimeTypes(mime, "image/*")) {
                imageMime = mime
                break
            }
        }
        val imageUri = item.uri?.takeIf { imageMime != null }
        val thumbnail = loadClipboardThumbnail(imageUri)
        val hasImage = imageMime != null
        val text = when {
            explicitText.isNotEmpty() -> explicitText
            hasImage -> null
            else -> item.coerceToText(this)?.toString()?.trim()
        }
        return PrimaryClipInspection(
            text = text,
            hasImage = hasImage,
            imageUri = imageUri,
            imageMime = imageMime,
            thumbnail = thumbnail,
        )
    }

    private fun loadClipboardThumbnail(imageUri: Uri?): Bitmap? {
        val uri = imageUri ?: return null
        val target = dp(18)
        val decoded = runCatching {
            contentResolver.openInputStream(uri)?.use { stream ->
                BitmapFactory.decodeStream(stream)
            }
        }.getOrNull() ?: return null
        return scaleBitmap(decoded, target)
    }

    private fun scaleBitmap(source: Bitmap, targetPx: Int): Bitmap {
        if (source.width <= targetPx && source.height <= targetPx) return source
        val scale = targetPx.toFloat() / maxOf(source.width, source.height).toFloat()
        val w = (source.width * scale).toInt().coerceAtLeast(1)
        val h = (source.height * scale).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(source, w, h, true)
    }

    private sealed class KeyAction {
        data class CommitChar(val value: Char) : KeyAction()
        data object Space : KeyAction()
        data object Backspace : KeyAction()
        data object Enter : KeyAction()
        data object Shift : KeyAction()
        data object Symbols : KeyAction()
        data object Letters : KeyAction()
        data object Emoji : KeyAction()
    }

    private data class KeySpec(
        val label: String,
        val widthWeight: Float = 1f,
        val action: KeyAction,
        val longPress: List<String> = emptyList(),
        val accent: Boolean = false,
        val visualLead: Float = 0f,
        val visualTrail: Float = 0f,
        val baseLabel: String = "",
    )

    private data class LetterBinding(val base: String, val visual: TextView)

    companion object {
        private const val COLOR_BG = 0xFF1C1C1E.toInt()
        private const val COLOR_KEY = 0xFF2C2C2E.toInt()
        private const val COLOR_TOOL = 0xFF3A3A3E.toInt()
        private const val COLOR_SELECTED = 0xFF3D6BFF.toInt()
        private const val COLOR_ENTER = 0xFF5B67F0.toInt()
        private const val COLOR_TEXT = 0xFFFFFFFF.toInt()
        private const val MAX_SOURCE_CHARS = 8000
        private const val KEY_HOLD_MS = 350L
        private const val ACCENT_SLOT_DP = 40
        private const val SUGGESTION_BAR_MIN_DP = 40
    }
}
