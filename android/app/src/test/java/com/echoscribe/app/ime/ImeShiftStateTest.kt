package com.echoscribe.app.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ImeShiftStateTest {
    @Test
    fun tapClearsAutoCapSoLowercaseCanFollowSentenceEnd() {
        val armed = ImeShiftState(autoCapNext = true)
        assertTrue(armed.lettersUppercase)
        assertTrue(armed.shiftHighlighted)

        val lowered = armed.tap()
        assertFalse(lowered.lettersUppercase)
        assertFalse(lowered.autoCapNext)
        assertFalse(lowered.shiftOnce)
        assertFalse(lowered.capsLock)
    }

    @Test
    fun tapFromLowercaseArmsOneShotShift() {
        val next = ImeShiftState().tap()
        assertTrue(next.shiftOnce)
        assertTrue(next.lettersUppercase)
        assertFalse(next.autoCapNext)
    }

    @Test
    fun tapFromOneShotShiftReturnsToLowercase() {
        val next = ImeShiftState(shiftOnce = true).tap()
        assertFalse(next.lettersUppercase)
        assertFalse(next.shiftOnce)
    }

    @Test
    fun tapFromCapsLockReturnsToLowercase() {
        val next = ImeShiftState(capsLock = true, autoCapNext = true).tap()
        assertFalse(next.capsLock)
        assertFalse(next.lettersUppercase)
        assertFalse(next.autoCapNext)
    }

    @Test
    fun longPressEntersCapsLock() {
        val next = ImeShiftState(autoCapNext = true).longPress()
        assertTrue(next.capsLock)
        assertFalse(next.shiftOnce)
        assertFalse(next.autoCapNext)
        assertTrue(next.lettersUppercase)
    }
}
