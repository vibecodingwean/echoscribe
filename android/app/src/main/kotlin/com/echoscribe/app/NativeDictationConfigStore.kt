package com.echoscribe.app

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import com.echoscribe.app.ime.ImeKeyboardLayout
import org.json.JSONArray
import org.json.JSONObject
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

data class CustomPromptEntry(
    val name: String,
    val prompt: String,
)

data class NativeDictationConfig(
    val enabled: Boolean,
    val floatingEnabled: Boolean,
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
    val voiceMode: String = "google",
    val autocorrectEnabled: Boolean = true,
    val autoCapitalizeEnabled: Boolean = true,
    val hapticFeedbackEnabled: Boolean = true,
    val soundFeedbackEnabled: Boolean = true,
    val opticalFeedbackEnabled: Boolean = true,
    val customTones: List<CustomPromptEntry> = emptyList(),
    val customGrammar: List<CustomPromptEntry> = emptyList(),
    val customAssistants: List<CustomPromptEntry> = emptyList(),
    val keyboardLayout: String = ImeKeyboardLayout.QWERTZ,
) {
    fun isReadyForDictation(): Boolean {
        return enabled && hasUsableProvider()
    }

    fun isReadyForFloatingDictation(): Boolean {
        return floatingEnabled && hasUsableProvider()
    }

    fun hasUsableProvider(): Boolean {
        if (provider == "localAi") {
            return supportsDictation && localAiLlmUrl.isNotBlank() && localAiWhisperUrl.isNotBlank()
        }
        return supportsDictation && provider != "anthropic" && apiKey.isNotBlank()
    }

    fun isEchoScribeVoiceMode(): Boolean = voiceMode.equals("echoscribe", ignoreCase = true)
}

class NativeDictationConfigStore(private val context: Context) {
    private val prefs = context.getSharedPreferences("floating_dictation_secure", Context.MODE_PRIVATE)

    fun save(args: Map<*, *>) {
        val previous = memory ?: loadFromDisk()
        val next = snapshotFrom(previous, args)
        val editor = prefs.edit()
        fun put(key: String, value: String, old: String?) {
            if (old != null && old == value) return
            write(editor, key, value)
        }
        if (args.containsKey("enabled")) {
            put("enabled", if (next.enabled) "1" else "0", previous?.let { if (it.enabled) "1" else "0" })
        }
        if (args.containsKey("floatingEnabled")) {
            put(
                "floatingEnabled",
                if (next.floatingEnabled) "1" else "0",
                previous?.let { if (it.floatingEnabled) "1" else "0" },
            )
        }
        put("provider", next.provider, previous?.provider)
        put("brandName", next.brandName, previous?.brandName)
        put("apiKey", next.apiKey, previous?.apiKey)
        put("targetLanguageCode", next.targetLanguageCode, previous?.targetLanguageCode)
        put("dictationPrompt", next.dictationPrompt, previous?.dictationPrompt)
        put("transcriptionModel", next.transcriptionModel, previous?.transcriptionModel)
        put("formattingModel", next.formattingModel, previous?.formattingModel)
        put("reasoningEffort", next.reasoningEffort, previous?.reasoningEffort)
        put(
            "supportsDictation",
            if (next.supportsDictation) "1" else "0",
            previous?.let { if (it.supportsDictation) "1" else "0" },
        )
        put("localAiLlmUrl", next.localAiLlmUrl, previous?.localAiLlmUrl)
        put("localAiWhisperUrl", next.localAiWhisperUrl, previous?.localAiWhisperUrl)
        if (args.containsKey("voiceMode")) {
            put("voiceMode", next.voiceMode, previous?.voiceMode)
        }
        if (args.containsKey("autocorrectEnabled")) {
            put(
                "autocorrectEnabled",
                if (next.autocorrectEnabled) "1" else "0",
                previous?.let { if (it.autocorrectEnabled) "1" else "0" },
            )
        }
        if (args.containsKey("autoCapitalizeEnabled")) {
            put(
                "autoCapitalizeEnabled",
                if (next.autoCapitalizeEnabled) "1" else "0",
                previous?.let { if (it.autoCapitalizeEnabled) "1" else "0" },
            )
        }
        if (args.containsKey("hapticFeedbackEnabled")) {
            put(
                "hapticFeedbackEnabled",
                if (next.hapticFeedbackEnabled) "1" else "0",
                previous?.let { if (it.hapticFeedbackEnabled) "1" else "0" },
            )
        }
        if (args.containsKey("soundFeedbackEnabled")) {
            put(
                "soundFeedbackEnabled",
                if (next.soundFeedbackEnabled) "1" else "0",
                previous?.let { if (it.soundFeedbackEnabled) "1" else "0" },
            )
        }
        if (args.containsKey("opticalFeedbackEnabled")) {
            put(
                "opticalFeedbackEnabled",
                if (next.opticalFeedbackEnabled) "1" else "0",
                previous?.let { if (it.opticalFeedbackEnabled) "1" else "0" },
            )
        }
        if (args.containsKey("customTones")) {
            put(
                "customTones",
                encodePromptEntries(next.customTones.map { mapOf("name" to it.name, "prompt" to it.prompt) }, "prompt"),
                previous?.let {
                    encodePromptEntries(it.customTones.map { e -> mapOf("name" to e.name, "prompt" to e.prompt) }, "prompt")
                },
            )
        }
        if (args.containsKey("customGrammar")) {
            put(
                "customGrammar",
                encodePromptEntries(
                    next.customGrammar.map { mapOf("name" to it.name, "instruction" to it.prompt) },
                    "instruction",
                ),
                previous?.let {
                    encodePromptEntries(
                        it.customGrammar.map { e -> mapOf("name" to e.name, "instruction" to e.prompt) },
                        "instruction",
                    )
                },
            )
        }
        if (args.containsKey("customAssistants")) {
            put(
                "customAssistants",
                encodePromptEntries(
                    next.customAssistants.map { mapOf("name" to it.name, "prompt" to it.prompt) },
                    "prompt",
                ),
                previous?.let {
                    encodePromptEntries(
                        it.customAssistants.map { e -> mapOf("name" to e.name, "prompt" to e.prompt) },
                        "prompt",
                    )
                },
            )
        }
        if (args.containsKey("keyboardLayout")) {
            put("keyboardLayout", next.keyboardLayout, previous?.keyboardLayout)
        }
        editor.apply()
        memory = next
    }

    fun saveVoiceMode(voiceMode: String) {
        val normalized = normalizeVoiceMode(voiceMode)
        if (memory?.voiceMode != normalized) {
            val editor = prefs.edit()
            write(editor, "voiceMode", normalized)
            editor.apply()
        }
        memory = memory?.copy(voiceMode = normalized)
    }

    fun loadVoiceMode(): String {
        return memory?.voiceMode ?: normalizeVoiceMode(read("voiceMode"))
    }

    fun saveKeyboardLayout(layout: String) {
        val normalized = ImeKeyboardLayout.normalize(layout, languageCode())
        if (memory?.keyboardLayout != normalized) {
            val editor = prefs.edit()
            write(editor, "keyboardLayout", normalized)
            editor.apply()
        }
        memory = memory?.copy(keyboardLayout = normalized)
    }

    fun loadKeyboardLayout(): String {
        memory?.keyboardLayout?.let { stored ->
            if (stored == ImeKeyboardLayout.QWERTY || stored == ImeKeyboardLayout.QWERTZ) {
                return stored
            }
        }
        return ImeKeyboardLayout.normalize(read("keyboardLayout"), languageCode())
    }

    fun peek(): NativeDictationConfig? = memory

    fun load(): NativeDictationConfig? {
        memory?.let { return it }
        return loadFromDisk()?.also { memory = it }
    }

    private fun loadFromDisk(): NativeDictationConfig? {
        val provider = read("provider") ?: return null
        return NativeDictationConfig(
            enabled = read("enabled") != "0",
            floatingEnabled = read("floatingEnabled") != "0",
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
            voiceMode = normalizeVoiceMode(read("voiceMode")),
            autocorrectEnabled = read("autocorrectEnabled") != "0",
            autoCapitalizeEnabled = read("autoCapitalizeEnabled") != "0",
            hapticFeedbackEnabled = read("hapticFeedbackEnabled") != "0",
            soundFeedbackEnabled = read("soundFeedbackEnabled") != "0",
            opticalFeedbackEnabled = read("opticalFeedbackEnabled") != "0",
            customTones = decodePromptEntries(read("customTones"), promptKey = "prompt"),
            customGrammar = decodePromptEntries(read("customGrammar"), promptKey = "instruction"),
            customAssistants = decodePromptEntries(read("customAssistants"), promptKey = "prompt"),
            keyboardLayout = ImeKeyboardLayout.normalize(read("keyboardLayout"), languageCode()),
        )
    }

    private fun snapshotFrom(previous: NativeDictationConfig?, args: Map<*, *>): NativeDictationConfig {
        fun flag(key: String, current: Boolean): Boolean {
            return if (args.containsKey(key)) args[key] != false else current
        }
        return NativeDictationConfig(
            enabled = flag("enabled", previous?.enabled ?: true),
            floatingEnabled = flag("floatingEnabled", previous?.floatingEnabled ?: true),
            provider = args["provider"]?.toString() ?: previous?.provider.orEmpty(),
            brandName = args["brandName"]?.toString() ?: previous?.brandName.orEmpty(),
            apiKey = args["apiKey"]?.toString() ?: previous?.apiKey.orEmpty(),
            targetLanguageCode = args["targetLanguageCode"]?.toString()
                ?: previous?.targetLanguageCode
                ?: "auto",
            dictationPrompt = args["dictationPrompt"]?.toString()
                ?: previous?.dictationPrompt
                ?: defaultDictationPrompt,
            transcriptionModel = args["transcriptionModel"]?.toString()
                ?: previous?.transcriptionModel.orEmpty(),
            formattingModel = args["formattingModel"]?.toString()
                ?: previous?.formattingModel.orEmpty(),
            reasoningEffort = args["reasoningEffort"]?.toString()
                ?: previous?.reasoningEffort.orEmpty(),
            supportsDictation = if (args.containsKey("supportsDictation")) {
                args["supportsDictation"] == true
            } else {
                previous?.supportsDictation == true
            },
            localAiLlmUrl = args["localAiLlmUrl"]?.toString() ?: previous?.localAiLlmUrl.orEmpty(),
            localAiWhisperUrl = args["localAiWhisperUrl"]?.toString()
                ?: previous?.localAiWhisperUrl.orEmpty(),
            voiceMode = if (args.containsKey("voiceMode")) {
                normalizeVoiceMode(args["voiceMode"]?.toString())
            } else {
                previous?.voiceMode ?: "google"
            },
            autocorrectEnabled = flag("autocorrectEnabled", previous?.autocorrectEnabled ?: true),
            autoCapitalizeEnabled = flag("autoCapitalizeEnabled", previous?.autoCapitalizeEnabled ?: true),
            hapticFeedbackEnabled = flag("hapticFeedbackEnabled", previous?.hapticFeedbackEnabled ?: true),
            soundFeedbackEnabled = flag("soundFeedbackEnabled", previous?.soundFeedbackEnabled ?: true),
            opticalFeedbackEnabled = flag("opticalFeedbackEnabled", previous?.opticalFeedbackEnabled ?: true),
            customTones = if (args.containsKey("customTones")) {
                decodePromptEntries(encodePromptEntries(args["customTones"], "prompt"), "prompt")
            } else {
                previous?.customTones ?: emptyList()
            },
            customGrammar = if (args.containsKey("customGrammar")) {
                decodePromptEntries(encodePromptEntries(args["customGrammar"], "instruction"), "instruction")
            } else {
                previous?.customGrammar ?: emptyList()
            },
            customAssistants = if (args.containsKey("customAssistants")) {
                decodePromptEntries(encodePromptEntries(args["customAssistants"], "prompt"), "prompt")
            } else {
                previous?.customAssistants ?: emptyList()
            },
            keyboardLayout = if (args.containsKey("keyboardLayout")) {
                ImeKeyboardLayout.normalize(args["keyboardLayout"]?.toString(), languageCode())
            } else {
                previous?.keyboardLayout ?: ImeKeyboardLayout.defaultForLanguage(languageCode())
            },
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

    private fun languageCode(): String {
        return if (Build.VERSION.SDK_INT >= 24) {
            context.resources.configuration.locales[0]?.language.orEmpty()
        } else {
            @Suppress("DEPRECATION")
            context.resources.configuration.locale?.language.orEmpty()
        }
    }

    private fun normalizeVoiceMode(value: String?): String {
        return if (value.equals("echoscribe", ignoreCase = true)) "echoscribe" else "google"
    }

    private fun encodePromptEntries(raw: Any?, promptKey: String): String {
        val array = JSONArray()
        when (raw) {
            is List<*> -> {
                raw.forEach { item ->
                    val map = item as? Map<*, *> ?: return@forEach
                    val name = map["name"]?.toString()?.trim().orEmpty()
                    val prompt = (map[promptKey] ?: map["prompt"] ?: map["instruction"])
                        ?.toString()
                        ?.trim()
                        .orEmpty()
                    if (name.isNotEmpty() && prompt.isNotEmpty()) {
                        array.put(
                            JSONObject()
                                .put("name", name)
                                .put(promptKey, prompt),
                        )
                    }
                }
            }
            is String -> {
                val trimmed = raw.trim()
                if (trimmed.startsWith("[")) {
                    runCatching {
                        val parsed = JSONArray(trimmed)
                        for (i in 0 until parsed.length()) {
                            val obj = parsed.optJSONObject(i) ?: continue
                            val name = obj.optString("name").trim()
                            val prompt = obj.optString(promptKey)
                                .ifBlank { obj.optString("prompt") }
                                .ifBlank { obj.optString("instruction") }
                                .trim()
                            if (name.isNotEmpty() && prompt.isNotEmpty()) {
                                array.put(
                                    JSONObject()
                                        .put("name", name)
                                        .put(promptKey, prompt),
                                )
                            }
                        }
                    }
                }
            }
        }
        return array.toString()
    }

    private fun decodePromptEntries(raw: String?, promptKey: String): List<CustomPromptEntry> {
        if (raw.isNullOrBlank()) return emptyList()
        return try {
            val array = JSONArray(raw)
            buildList {
                for (i in 0 until array.length()) {
                    val obj = array.optJSONObject(i) ?: continue
                    val name = obj.optString("name").trim()
                    val prompt = obj.optString(promptKey)
                        .ifBlank { obj.optString("prompt") }
                        .ifBlank { obj.optString("instruction") }
                        .trim()
                    if (name.isNotEmpty() && prompt.isNotEmpty()) {
                        add(CustomPromptEntry(name = name, prompt = prompt))
                    }
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
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
        const val ACTION_CONFIG_CHANGED = "com.echoscribe.app.KEYBOARD_IME_CONFIG_CHANGED"
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

        @Volatile
        private var memory: NativeDictationConfig? = null
    }
}
