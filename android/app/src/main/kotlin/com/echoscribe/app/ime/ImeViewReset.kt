package com.echoscribe.app.ime

/**
 * Pure reset rules when the IME input view finishes or a new field starts,
 * so sheets (emoji/clipboard/AI) do not survive app switches.
 */
object ImeViewReset {
    data class FinishRequest(
        val activeSheet: ImeSheetKind? = null,
        val lettersLayer: Boolean = true,
        val dismissAccentPopup: Boolean = true,
        val cancelPendingKey: Boolean = true,
        val clearVoiceLog: Boolean = true,
    )

    fun finishInputView(): FinishRequest = FinishRequest()

    fun shouldClearSheet(restarting: Boolean, sensitiveField: Boolean): Boolean {
        return sensitiveField || !restarting
    }
}
