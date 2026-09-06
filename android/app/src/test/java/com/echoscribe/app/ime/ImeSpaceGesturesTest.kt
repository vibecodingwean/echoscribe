package com.echoscribe.app.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ImeSpaceGesturesTest {
    @Test
    fun secondSpaceAfterWordBecomesPeriod() {
        assertTrue(ImeSpaceGestures.shouldInsertPeriod("Hallo "))
        assertTrue(ImeSpaceGestures.shouldInsertPeriod("x9 "))
        assertFalse(ImeSpaceGestures.shouldInsertPeriod("Hallo"))
        assertFalse(ImeSpaceGestures.shouldInsertPeriod(" "))
        assertFalse(ImeSpaceGestures.shouldInsertPeriod("Hallo. "))
        assertFalse(ImeSpaceGestures.shouldInsertPeriod("Hallo  "))
    }

    @Test
    fun cursorStepsRoundHalfAwayFromZero() {
        val slot = 12f
        assertEquals(0, ImeSpaceGestures.cursorSteps(0f, slot))
        assertEquals(0, ImeSpaceGestures.cursorSteps(5f, slot))
        assertEquals(1, ImeSpaceGestures.cursorSteps(6f, slot))
        assertEquals(-1, ImeSpaceGestures.cursorSteps(-6f, slot))
        assertEquals(2, ImeSpaceGestures.cursorSteps(24f, slot))
    }

    @Test
    fun clampCursorStaysInRange() {
        assertEquals(3, ImeSpaceGestures.clampCursor(beforeLen = 3, afterLen = 2, steps = 0))
        assertEquals(1, ImeSpaceGestures.clampCursor(beforeLen = 3, afterLen = 2, steps = -2))
        assertEquals(0, ImeSpaceGestures.clampCursor(beforeLen = 3, afterLen = 2, steps = -99))
        assertEquals(5, ImeSpaceGestures.clampCursor(beforeLen = 3, afterLen = 2, steps = 99))
    }

    @Test
    fun moveIndexKeepsColumnAcrossLines() {
        val text = "abc\nxy\nzzzz"
        assertEquals(5, ImeSpaceGestures.moveIndex(text, startIndex = 1, charSteps = 0, lineSteps = 1))
        assertEquals(1, ImeSpaceGestures.moveIndex(text, startIndex = 5, charSteps = 0, lineSteps = -1))
        assertEquals(8, ImeSpaceGestures.moveIndex(text, startIndex = 1, charSteps = 0, lineSteps = 2))
        assertEquals(3, ImeSpaceGestures.moveIndex(text, startIndex = 1, charSteps = 2, lineSteps = 0))
        assertEquals(0, ImeSpaceGestures.moveIndex(text, startIndex = 0, charSteps = -9, lineSteps = -9))
        assertEquals(text.length, ImeSpaceGestures.moveIndex(text, startIndex = 2, charSteps = 99, lineSteps = 99))
    }

    @Test
    fun loupeSnippetMarksCaret() {
        val snippet = ImeSpaceGestures.loupeSnippet("hello world", 6, window = 8)
        assertTrue(snippet.contains('│'))
        assertFalse(snippet.contains('\n'))
        assertEquals("ello│ wor", ImeSpaceGestures.loupeSnippet("hello world", 5, window = 8))
    }
}
