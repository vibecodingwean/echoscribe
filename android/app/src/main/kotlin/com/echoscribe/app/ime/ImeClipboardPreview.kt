package com.echoscribe.app.ime

/**
 * Pure clipboard chip classification/preview helpers for the IME toolbar clipboard preview.
 * URI/bitmap IO stays in [EchoScribeImeService].
 */
object ImeClipboardPreview {
    const val DEFAULT_MAX_CHARS = 16

    enum class Kind {
        Empty,
        Text,
        Image,
    }

    data class Snapshot(
        val kind: Kind,
        val textPreview: String = "",
    )

    fun classify(
        text: String?,
        hasImage: Boolean,
        maxChars: Int = DEFAULT_MAX_CHARS,
    ): Snapshot {
        val preview = truncateOneLine(text.orEmpty(), maxChars)
        if (preview.isNotEmpty()) {
            return Snapshot(kind = Kind.Text, textPreview = preview)
        }
        if (hasImage) {
            return Snapshot(kind = Kind.Image)
        }
        return Snapshot(kind = Kind.Empty)
    }

    fun truncateOneLine(text: String, maxChars: Int = DEFAULT_MAX_CHARS): String {
        if (maxChars <= 0) return ""
        val oneLine = text
            .replace('\r', ' ')
            .replace('\n', ' ')
            .replace('\t', ' ')
            .trim()
            .replace(Regex("\\s+"), " ")
        if (oneLine.isEmpty()) return ""
        if (oneLine.length <= maxChars) return oneLine
        if (maxChars == 1) return "…"
        return oneLine.take(maxChars - 1).trimEnd() + "…"
    }

    fun shouldShowChip(
        sensitiveField: Boolean,
        recordingOrProcessing: Boolean,
        voiceLog: String?,
        snapshot: Snapshot,
    ): Boolean {
        if (sensitiveField) return false
        if (recordingOrProcessing) return false
        if (!voiceLog.isNullOrBlank()) return false
        return snapshot.kind != Kind.Empty
    }
}
