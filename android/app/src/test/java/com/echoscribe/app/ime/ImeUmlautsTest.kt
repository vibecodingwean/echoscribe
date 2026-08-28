package com.echoscribe.app.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ImeUmlautsTest {
    @Test
    fun longPressOnAousCommitsPrimaryUmlautLowercaseMidWord() {
        assertEquals("ä", ImeUmlauts.primary("a"))
        assertEquals("ö", ImeUmlauts.primary("o"))
        assertEquals("ü", ImeUmlauts.primary("u"))
        assertEquals("ß", ImeUmlauts.primary("s"))
        assertEquals("ö", ImeUmlauts.applyCase("ö", false))
        assertEquals("ä", ImeUmlauts.applyCase("ä", false))
    }

    @Test
    fun umlautCaseFollowsShiftAtCommitTimeNotStaleKeyLabels() {
        assertEquals("Ö", ImeUmlauts.applyCase("ö", true))
        assertEquals("Ä", ImeUmlauts.applyCase("ä", true))
        assertEquals("Ü", ImeUmlauts.applyCase("ü", true))
        assertEquals("ẞ", ImeUmlauts.applyCase("ß", true))
        assertEquals("ö", ImeUmlauts.applyCase("Ö", false))
        assertEquals("ß", ImeUmlauts.applyCase("ẞ", false))
    }

    @Test
    fun otherLettersKeepAccentPopupNotPrimaryUmlaut() {
        assertNull(ImeUmlauts.primary("e"))
        assertEquals(listOf("é", "è", "ê", "ë"), ImeUmlauts.popupAccents("e"))
        assertTrue(ImeUmlauts.hasHold("o"))
        assertTrue(ImeUmlauts.hasHold("e"))
        assertTrue(!ImeUmlauts.hasHold("q"))
    }
}
