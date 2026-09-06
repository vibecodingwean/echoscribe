package com.echoscribe.app.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ImeViewResetTest {
    @Test
    fun finishInputViewRequestsLettersLayerAndNullSheet() {
        val finish = ImeViewReset.finishInputView()
        assertNull(finish.activeSheet)
        assertTrue(finish.lettersLayer)
        assertTrue(finish.dismissAccentPopup)
        assertTrue(finish.cancelPendingKey)
        assertTrue(finish.clearVoiceLog)
    }

    @Test
    fun startInputClearsSheetWhenNotRestartingOrSensitive() {
        assertTrue(ImeViewReset.shouldClearSheet(restarting = false, sensitiveField = false))
        assertTrue(ImeViewReset.shouldClearSheet(restarting = false, sensitiveField = true))
        assertTrue(ImeViewReset.shouldClearSheet(restarting = true, sensitiveField = true))
        assertFalse(ImeViewReset.shouldClearSheet(restarting = true, sensitiveField = false))
    }

    @Test
    fun finishRequestDefaultsMatchExpectedShape() {
        assertEquals(ImeViewReset.FinishRequest(), ImeViewReset.finishInputView())
    }
}
