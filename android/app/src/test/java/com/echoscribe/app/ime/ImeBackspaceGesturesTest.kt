package com.echoscribe.app.ime

import org.junit.Assert.assertEquals
import org.junit.Test

class ImeBackspaceGesturesTest {
    @Test
    fun wordDeleteCountIncludesTrailingWhitespaceThenWord() {
        assertEquals(0, ImeBackspaceGestures.wordDeleteCount(""))
        assertEquals(1, ImeBackspaceGestures.wordDeleteCount("a"))
        assertEquals(6, ImeBackspaceGestures.wordDeleteCount("hello "))
        assertEquals(5, ImeBackspaceGestures.wordDeleteCount("hello"))
        assertEquals(4, ImeBackspaceGestures.wordDeleteCount("ab  "))
        assertEquals(3, ImeBackspaceGestures.wordDeleteCount("xy\n"))
    }

    @Test
    fun extraWordsFromLeftSwipe() {
        val slot = 40f
        assertEquals(0, ImeBackspaceGestures.extraWordsFromSwipe(10f, slot))
        assertEquals(0, ImeBackspaceGestures.extraWordsFromSwipe(-10f, slot))
        assertEquals(1, ImeBackspaceGestures.extraWordsFromSwipe(-40f, slot))
        assertEquals(2, ImeBackspaceGestures.extraWordsFromSwipe(-80f, slot))
    }
}
