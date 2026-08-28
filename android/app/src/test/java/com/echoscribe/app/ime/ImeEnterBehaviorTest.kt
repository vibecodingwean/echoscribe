package com.echoscribe.app.ime

import android.text.InputType
import android.view.inputmethod.EditorInfo
import org.junit.Assert.assertEquals
import org.junit.Test

class ImeEnterBehaviorTest {
    @Test
    fun singleLineSearchPerformsEditorAction() {
        assertEquals(
            ImeEnterBehavior.Outcome.EditorAction,
            ImeEnterBehavior.decide(
                InputType.TYPE_CLASS_TEXT,
                EditorInfo.IME_ACTION_SEARCH,
            ),
        )
    }

    @Test
    fun singleLineUnspecifiedSendsEnterKeyNotNewline() {
        assertEquals(
            ImeEnterBehavior.Outcome.SendEnterKey,
            ImeEnterBehavior.decide(
                InputType.TYPE_CLASS_TEXT,
                EditorInfo.IME_ACTION_UNSPECIFIED,
            ),
        )
    }

    @Test
    fun singleLineGoAndDonePerformAction() {
        assertEquals(
            ImeEnterBehavior.Outcome.EditorAction,
            ImeEnterBehavior.decide(InputType.TYPE_CLASS_TEXT, EditorInfo.IME_ACTION_GO),
        )
        assertEquals(
            ImeEnterBehavior.Outcome.EditorAction,
            ImeEnterBehavior.decide(InputType.TYPE_CLASS_TEXT, EditorInfo.IME_ACTION_DONE),
        )
    }

    @Test
    fun multiLineInsertsNewline() {
        assertEquals(
            ImeEnterBehavior.Outcome.Newline,
            ImeEnterBehavior.decide(
                InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE,
                EditorInfo.IME_ACTION_UNSPECIFIED,
            ),
        )
        assertEquals(
            ImeEnterBehavior.Outcome.Newline,
            ImeEnterBehavior.decide(
                InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE,
                EditorInfo.IME_ACTION_DONE or EditorInfo.IME_FLAG_NO_ENTER_ACTION,
            ),
        )
    }
}
