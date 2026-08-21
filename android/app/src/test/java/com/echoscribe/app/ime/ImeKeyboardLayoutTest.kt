package com.echoscribe.app.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class ImeKeyboardLayoutTest {
    @Test
    fun qwertzSpacebarIsDeutschNotEnglish() {
        assertEquals("Deutsch", ImeKeyboardLayout.spaceLabel(ImeKeyboardLayout.QWERTZ))
        assertNotEquals("English", ImeKeyboardLayout.spaceLabel(ImeKeyboardLayout.QWERTZ))
        assertEquals("English", ImeKeyboardLayout.spaceLabel(ImeKeyboardLayout.QWERTY))
    }

    @Test
    fun qwertzAndQwertySwapYAndZ() {
        assertEquals(
            listOf("q", "w", "e", "r", "t", "z", "u", "i", "o", "p"),
            ImeKeyboardLayout.row1(ImeKeyboardLayout.QWERTZ),
        )
        assertEquals(
            listOf("y", "x", "c", "v", "b", "n", "m"),
            ImeKeyboardLayout.row3(ImeKeyboardLayout.QWERTZ),
        )
        assertEquals(
            listOf("q", "w", "e", "r", "t", "y", "u", "i", "o", "p"),
            ImeKeyboardLayout.row1(ImeKeyboardLayout.QWERTY),
        )
        assertEquals(
            listOf("z", "x", "c", "v", "b", "n", "m"),
            ImeKeyboardLayout.row3(ImeKeyboardLayout.QWERTY),
        )
        assertEquals(ImeKeyboardLayout.row2(ImeKeyboardLayout.QWERTZ), ImeKeyboardLayout.row2(ImeKeyboardLayout.QWERTY))
    }

    @Test
    fun globeCyclesOnlyEchoScribeLayouts() {
        assertEquals(ImeKeyboardLayout.QWERTY, ImeKeyboardLayout.cycle(ImeKeyboardLayout.QWERTZ))
        assertEquals(ImeKeyboardLayout.QWERTZ, ImeKeyboardLayout.cycle(ImeKeyboardLayout.QWERTY))
        assertEquals(ImeKeyboardLayout.QWERTY, ImeKeyboardLayout.cycle("Deutsch"))
    }

    @Test
    fun displayLetterDoesNotRebuildCasingFromCommittedGlyph() {
        assertEquals("q", ImeKeyboardLayout.displayLetter("q", false))
        assertEquals("Q", ImeKeyboardLayout.displayLetter("q", true))
        assertEquals("ẞ", ImeKeyboardLayout.displayLetter("ß", true))
    }

    @Test
    fun unsetLayoutFollowsDeviceLanguage() {
        assertEquals(ImeKeyboardLayout.QWERTZ, ImeKeyboardLayout.defaultForLanguage("de"))
        assertEquals(ImeKeyboardLayout.QWERTY, ImeKeyboardLayout.defaultForLanguage("en"))
        assertEquals(ImeKeyboardLayout.QWERTZ, ImeKeyboardLayout.normalize(null, "de"))
        assertEquals(ImeKeyboardLayout.QWERTY, ImeKeyboardLayout.normalize("", "en"))
        assertEquals(ImeKeyboardLayout.QWERTY, ImeKeyboardLayout.normalize("QWERTY", "de"))
    }
}
