package com.echoscribe.app

import android.content.Context
import java.security.MessageDigest

/** Reads the same versioned provider grant written by Flutter SharedPreferences. */
class NativeAiConsent(context: Context) {
    private val preferences = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    fun hasGrant(config: NativeDictationConfig, use: String): Boolean {
        if (use !in setOf("text", "fileAudio")) return false
        val provider = config.provider
        if (provider !in setOf("openai", "gemini", "anthropic", "xai", "elevenLabs", "localAi")) {
            return false
        }
        val scope = when (provider) {
            "gemini" -> "2:gemini-adult-paid-2026-03"
            "localAi" -> {
                val endpoint = "${config.localAiLlmUrl}|${config.localAiWhisperUrl}".trim()
                val digest = MessageDigest.getInstance("SHA-256")
                    .digest(endpoint.toByteArray(Charsets.UTF_8))
                    .joinToString("") { "%02x".format(it.toInt() and 0xff) }
                "2:$digest"
            }
            else -> "2"
        }
        return preferences.getString("flutter.ai_provider_consent_v2_${provider}_$use", null) == scope
    }
}
