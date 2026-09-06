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

    @Test
    fun holdListForUStartsWithPrimaryUmlautAndDefaultIndexIsZero() {
        val glyphs = ImeAccentHold.holdGlyphs("u")
        assertEquals("ü", glyphs.first())
        assertEquals(0, ImeAccentHold.defaultIndex("u"))
        assertTrue(glyphs.size > 1)
        assertEquals("ä", ImeAccentHold.holdGlyphs("a").first())
        assertEquals("ö", ImeAccentHold.holdGlyphs("o").first())
        assertEquals("ß", ImeAccentHold.holdGlyphs("s").first())
        assertEquals(listOf("é", "è", "ê", "ë"), ImeAccentHold.holdGlyphs("e"))
    }

    @Test
    fun slidingPastThresholdSelectsNeighborGlyph() {
        val count = ImeAccentHold.holdGlyphs("u").size
        val slot = 40f
        assertEquals(0, ImeAccentHold.indexFromHorizontalDelta(0f, slot, count, startIndex = 0))
        assertEquals(0, ImeAccentHold.indexFromHorizontalDelta(19f, slot, count, startIndex = 0))
        assertEquals(1, ImeAccentHold.indexFromHorizontalDelta(20f, slot, count, startIndex = 0))
        assertEquals(2, ImeAccentHold.indexFromHorizontalDelta(80f, slot, count, startIndex = 0))
        assertEquals(0, ImeAccentHold.indexFromHorizontalDelta(-10f, slot, count, startIndex = 0))
        assertEquals(count - 1, ImeAccentHold.indexFromHorizontalDelta(10_000f, slot, count, startIndex = 0))
    }
}
