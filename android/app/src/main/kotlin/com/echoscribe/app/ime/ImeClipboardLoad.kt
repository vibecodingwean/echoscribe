package com.echoscribe.app.ime

/**
 * Clipboard chip load policy: never block first keyboard paint, never full-decode images.
 */
object ImeClipboardLoad {
    const val THUMB_TARGET_DP = 18

    fun inSampleSize(srcWidth: Int, srcHeight: Int, targetPx: Int): Int {
        if (srcWidth <= 0 || srcHeight <= 0 || targetPx <= 0) return 1
        var sample = 1
        val longest = maxOf(srcWidth, srcHeight)
        while (longest / (sample * 2) >= targetPx) {
            sample *= 2
        }
        return sample
    }
}
