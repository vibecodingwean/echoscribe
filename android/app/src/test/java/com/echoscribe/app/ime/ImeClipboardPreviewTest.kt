package com.echoscribe.app.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ImeClipboardPreviewTest {
    @Test
    fun emptyWhenNoTextAndNoImage() {
        val snap = ImeClipboardPreview.classify(text = null, hasImage = false)
        assertEquals(ImeClipboardPreview.Kind.Empty, snap.kind)
        assertEquals("", snap.textPreview)
    }

    @Test
    fun prefersTextOverImage() {
        val snap = ImeClipboardPreview.classify(text = "hello world", hasImage = true)
        assertEquals(ImeClipboardPreview.Kind.Text, snap.kind)
        assertEquals("hello world", snap.textPreview)
    }

    @Test
    fun imageWhenBlankTextAndHasImage() {
        val snap = ImeClipboardPreview.classify(text = "  \n\t ", hasImage = true)
        assertEquals(ImeClipboardPreview.Kind.Image, snap.kind)
        assertEquals("", snap.textPreview)
    }

    @Test
    fun truncatesToOneLineWithEllipsis() {
        val raw = "line one\nline two   with   spaces"
        val preview = ImeClipboardPreview.truncateOneLine(raw, maxChars = 18)
        assertEquals("line one line two…", preview)
        assertFalse(preview.contains('\n'))
    }

    @Test
    fun defaultClassifyTruncatesToSixteenWithEllipsis() {
        val long = "abcdefghijklmnopqrstuvwxyz0123456789"
        val snap = ImeClipboardPreview.classify(text = long, hasImage = false)
        assertEquals(ImeClipboardPreview.Kind.Text, snap.kind)
        assertTrue(snap.textPreview.length <= ImeClipboardPreview.DEFAULT_MAX_CHARS)
        assertTrue(snap.textPreview.endsWith("…"))
        assertEquals(16, snap.textPreview.length)
        assertEquals("abcdefghijklmno…", snap.textPreview)
    }

    @Test
    fun chipHiddenForSensitiveOrDictationPriority() {
        val text = ImeClipboardPreview.classify("clip", hasImage = false)
        assertFalse(
            ImeClipboardPreview.shouldShowChip(
                sensitiveField = true,
                recordingOrProcessing = false,
                voiceLog = null,
                snapshot = text,
            ),
        )
        assertFalse(
            ImeClipboardPreview.shouldShowChip(
                sensitiveField = false,
                recordingOrProcessing = true,
                voiceLog = null,
                snapshot = text,
            ),
        )
        assertFalse(
            ImeClipboardPreview.shouldShowChip(
                sensitiveField = false,
                recordingOrProcessing = false,
                voiceLog = "🎙️ Recording…",
                snapshot = text,
            ),
        )
        assertTrue(
            ImeClipboardPreview.shouldShowChip(
                sensitiveField = false,
                recordingOrProcessing = false,
                voiceLog = null,
                snapshot = text,
            ),
        )
        assertFalse(
            ImeClipboardPreview.shouldShowChip(
                sensitiveField = false,
                recordingOrProcessing = false,
                voiceLog = null,
                snapshot = ImeClipboardPreview.classify(null, hasImage = false),
            ),
        )
    }
}
