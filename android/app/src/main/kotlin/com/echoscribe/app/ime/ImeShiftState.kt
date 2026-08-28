package com.echoscribe.app.ime

data class ImeShiftState(
    val capsLock: Boolean = false,
    val shiftOnce: Boolean = false,
    val autoCapNext: Boolean = false,
) {
    val lettersUppercase: Boolean
        get() = capsLock || shiftOnce || autoCapNext

    val shiftHighlighted: Boolean
        get() = capsLock || shiftOnce || autoCapNext

    fun tap(): ImeShiftState {
        if (capsLock) {
            return ImeShiftState()
        }
        if (shiftOnce || autoCapNext) {
            return copy(shiftOnce = false, autoCapNext = false)
        }
        return copy(shiftOnce = true)
    }

    fun longPress(): ImeShiftState {
        return ImeShiftState(capsLock = true)
    }
}
