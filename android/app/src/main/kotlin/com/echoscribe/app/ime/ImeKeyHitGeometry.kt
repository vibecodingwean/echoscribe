package com.echoscribe.app.ime

/**
 * Visual keycaps are smaller than the tappable cell, matching AOSP LatinIME /
 * OpenBoard: the drawn key is inset from the hit box, and the cap sits high in
 * the cell because the finger pad contacts below the intended point.
 *
 * Main-grid [verticalCorrection] in OpenBoard is 0.0dp. The more-keys popup
 * uses about -26.4dp (Holo) so a finger covering the popup still hits it.
 */
object ImeKeyHitGeometry {
    const val MAIN_VERTICAL_CORRECTION_DP = 0
    const val POPUP_VERTICAL_CORRECTION_DP = -26

    data class InsetDp(val left: Int, val top: Int, val right: Int, val bottom: Int)
    data class PaddingDp(val top: Int, val bottom: Int)

    val visualInsetDp = InsetDp(left = 2, top = 2, right = 2, bottom = 8)
    val labelPaddingDp = PaddingDp(top = 0, bottom = 6)

    fun correctedTouchY(rawY: Float, popup: Boolean): Float {
        val correction = if (popup) POPUP_VERTICAL_CORRECTION_DP else MAIN_VERTICAL_CORRECTION_DP
        return rawY + correction
    }
}
