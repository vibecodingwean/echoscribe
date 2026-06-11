package com.echoscribe.app

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

data class NativeDictationConfig(
    val enabled: Boolean,
    val provider: String,
    val brandName: String,
    val apiKey: String,
    val targetLanguageCode: String,
    val dictationPrompt: String,
    val transcriptionModel: String,
    val formattingModel: String,
    val reasoningEffort: String,
    val supportsDictation: Boolean,
    val localAiLlmUrl: String,
    val localAiWhisperUrl: String,
) {
    fun isReadyForDictation(): Boolean {
        return enabled && hasUsableProvider()
    }

    fun hasUsableProvider(): Boolean {
        if (provider == "localAi") {
            return supportsDictation && localAiLlmUrl.isNotBlank() && localAiWhisperUrl.isNotBlank()
        }
        return supportsDictation && provider != "anthropic" && apiKey.isNotBlank()
    }
}

class NativeDictationConfigStore(private val context: Context) {
    private val prefs = context.getSharedPreferences("floating_dictation_secure", Context.MODE_PRIVATE)

    fun save(args: Map<*, *>) {
        val editor = prefs.edit()
        write(editor, "enabled", if (args["enabled"] == false) "0" else "1")
        write(editor, "provider", args["provider"]?.toString().orEmpty())
        write(editor, "brandName", args["brandName"]?.toString().orEmpty())
        write(editor, "apiKey", args["apiKey"]?.toString().orEmpty())
        write(editor, "targetLanguageCode", args["targetLanguageCode"]?.toString().orEmpty())
        write(editor, "dictationPrompt", args["dictationPrompt"]?.toString().orEmpty())
        write(editor, "transcriptionModel", args["transcriptionModel"]?.toString().orEmpty())
        write(editor, "formattingModel", args["formattingModel"]?.toString().orEmpty())
        write(editor, "reasoningEffort", args["reasoningEffort"]?.toString().orEmpty())
        write(editor, "supportsDictation", if (args["supportsDictation"] == true) "1" else "0")
        write(editor, "localAiLlmUrl", args["localAiLlmUrl"]?.toString().orEmpty())
        write(editor, "localAiWhisperUrl", args["localAiWhisperUrl"]?.toString().orEmpty())
        editor.apply()
    }

    fun load(): NativeDictationConfig? {
        val provider = read("provider") ?: return null
        return NativeDictationConfig(
            enabled = read("enabled") != "0",
            provider = provider,
            brandName = read("brandName").orEmpty(),
            apiKey = read("apiKey").orEmpty(),
            targetLanguageCode = read("targetLanguageCode").ifBlankOrNull("auto"),
            dictationPrompt = read("dictationPrompt").dictationPromptOrDefault(),
            transcriptionModel = read("transcriptionModel").orEmpty(),
            formattingModel = read("formattingModel").orEmpty(),
            reasoningEffort = read("reasoningEffort").orEmpty(),
            supportsDictation = read("supportsDictation") == "1",
            localAiLlmUrl = read("localAiLlmUrl").orEmpty(),
            localAiWhisperUrl = read("localAiWhisperUrl").orEmpty(),
        )
    }

    private fun write(editor: android.content.SharedPreferences.Editor, key: String, value: String) {
        editor.putString(key, encrypt(value))
    }

    private fun read(key: String): String? {
        val encoded = prefs.getString(key, null) ?: return null
        return decrypt(encoded)
    }

    private fun encrypt(value: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        val combined = cipher.iv + encrypted
        return Base64.encodeToString(combined, Base64.NO_WRAP)
    }

    private fun decrypt(encoded: String): String? {
        return try {
            val combined = Base64.decode(encoded, Base64.NO_WRAP)
            if (combined.size <= 12) return null
            val iv = combined.copyOfRange(0, 12)
            val encrypted = combined.copyOfRange(12, combined.size)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, iv))
            String(cipher.doFinal(encrypted), Charsets.UTF_8)
        } catch (_: Exception) {
            null
        }
    }

    private fun secretKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = keyStore.getEntry(keyAlias, null) as? KeyStore.SecretKeyEntry
        if (existing != null) return existing.secretKey

        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        val spec = KeyGenParameterSpec.Builder(
            keyAlias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true)
            .build()
        generator.init(spec)
        return generator.generateKey()
    }

    private fun String?.ifBlankOrNull(fallback: String): String {
        return if (this == null || isBlank()) fallback else this
    }

    private fun String?.dictationPromptOrDefault(): String {
        val prompt = this?.trim().orEmpty()
        return if (prompt.isBlank() || isLegacyDefaultDictationPrompt(prompt)) {
            defaultDictationPrompt
        } else {
            prompt
        }
    }

    private fun isLegacyDefaultDictationPrompt(prompt: String): Boolean {
        return prompt.startsWith("Formatiere den folgenden") ||
            prompt.startsWith("Polish this dictated raw transcript") ||
            (prompt.startsWith("Clean up this dictated transcript for direct text input.") &&
                (prompt.contains("Add 0-2 fitting emojis only when natural.") ||
                    prompt.contains("Add 1-2 fitting emojis only when natural.") ||
                    prompt.contains("Add 1-2 fitting emojis when natural.")))
    }

    companion object {
        private const val keyAlias = "echoscribe_floating_dictation_config"
        private const val defaultDictationPrompt =
            "Rewrite this dictated transcript for direct text input. " +
                "Output in the same language as the input; for mixed or unclear input, use the dominant language. " +
                "Keep the core meaning, tone level, names, and numbers, but make it polite, respectful, and natural. " +
                "Remove filler words and speech artifacts. " +
                "Never preserve insults, profanity, slurs, threats, or aggressive wording; turn them into calm, friendly wording with the same intent. " +
                "Do not summarize. " +
                "For emails or lists, add clear paragraphs, line breaks, and bullets when implied. " +
                "Add 1-2 fitting emojis when natural. " +
                "Return only the final text."
    }
}
