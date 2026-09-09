package com.echoscribe.app.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ImeKeyHitGeometryTest {
    @Test
    fun visualKeycapIsInsetFromHitCell() {
        val inset = ImeKeyHitGeometry.visualInsetDp
        assertEquals(2, inset.left)
        assertEquals(2, inset.right)
        assertTrue(inset.top > 0)
        assertTrue(inset.bottom > 0)
    }

    @Test
    fun visualKeycapSitsAboveHitCellCenter() {
        val inset = ImeKeyHitGeometry.visualInsetDp
        assertTrue(
            "Fat-finger occlusion: more bottom inset than top so the drawn key sits high in the hit cell",
            inset.bottom > inset.top,
        )
        assertEquals(2, inset.top)
        assertEquals(8, inset.bottom)
    }

    @Test
    fun labelSitsInUpperPartOfHitCell() {
        val pad = ImeKeyHitGeometry.labelPaddingDp
        assertTrue(pad.bottom > pad.top)
        assertEquals(0, pad.top)
        assertEquals(6, pad.bottom)
    }

    @Test
    fun mainKeyboardTouchYMatchesAospZeroCorrection() {
        assertEquals(0, ImeKeyHitGeometry.MAIN_VERTICAL_CORRECTION_DP)
        assertEquals(120f, ImeKeyHitGeometry.correctedTouchY(120f, popup = false), 0.01f)
    }

    @Test
    fun popupTouchYUsesAospHoloBias() {
        assertEquals(-26, ImeKeyHitGeometry.POPUP_VERTICAL_CORRECTION_DP)
        assertEquals(94f, ImeKeyHitGeometry.correctedTouchY(120f, popup = true), 0.01f)
    }
}
