package com.echoscribe.app.ime

import android.text.InputType
import android.view.inputmethod.EditorInfo

object ImeEnterBehavior {
    enum class Outcome {
        Newline,
        EditorAction,
        SendEnterKey,
    }

    fun actionId(imeOptions: Int): Int = imeOptions and EditorInfo.IME_MASK_ACTION

    fun decide(inputType: Int, imeOptions: Int): Outcome {
        val multiLine = inputType and InputType.TYPE_TEXT_FLAG_MULTI_LINE != 0
        val noEnterAction = imeOptions and EditorInfo.IME_FLAG_NO_ENTER_ACTION != 0
        val action = actionId(imeOptions)
        val explicitAction =
            action != EditorInfo.IME_ACTION_NONE &&
                action != EditorInfo.IME_ACTION_UNSPECIFIED

        if (!multiLine) {
            return if (explicitAction && !noEnterAction) Outcome.EditorAction else Outcome.SendEnterKey
        }
        if (noEnterAction || !explicitAction) return Outcome.Newline
        return Outcome.EditorAction
    }
}
