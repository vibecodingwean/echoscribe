package com.echoscribe.app.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ImeClipboardLoadTest {
    @Test
    fun smallImageKeepsSample1() {
        assertEquals(1, ImeClipboardLoad.inSampleSize(18, 18, 18))
        assertEquals(1, ImeClipboardLoad.inSampleSize(32, 24, 18))
    }

    @Test
    fun photoUsesPowerOfTwoDownsample() {
        val sample = ImeClipboardLoad.inSampleSize(4032, 3024, 18)
        assertTrue(sample >= 64)
        assertEquals(0, sample and (sample - 1))
    }

    @Test
    fun invalidSizesStaySafe() {
        assertEquals(1, ImeClipboardLoad.inSampleSize(0, 100, 18))
        assertEquals(1, ImeClipboardLoad.inSampleSize(100, 100, 0))
    }
}
