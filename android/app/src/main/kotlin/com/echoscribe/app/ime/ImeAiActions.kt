package com.echoscribe.app.ime

import com.echoscribe.app.CustomPromptEntry
import com.echoscribe.app.NativeDictationConfig
import com.echoscribe.app.R

enum class ImeSheetKind {
    Grammar,
    Tone,
    Translate,
    Emoji,
    Clipboard,
    More,
}

data class ImeChip(
    val id: String,
    val label: String,
    val prompt: String,
    val usesClipboard: Boolean = false,
)

object ImeAiActions {
    fun grammarChips(config: NativeDictationConfig?): List<ImeChip> {
        val builtIn = listOf(
            ImeChip("grammar_fix", "✍️ Grammar", "Fix the grammar and spelling. Keep meaning and language. Return only the corrected text."),
            ImeChip(
                "reply",
                "💬 Reply",
                "The text below is a copied message from the clipboard, not the input field. Write a concise, natural reply to that copied message. Keep the same language. Return only the reply.",
                usesClipboard = true,
            ),
            ImeChip(
                "rephrase",
                "🔄 Rephrase",
                "Rephrase this text in the same language as the input. Do not translate. Keep meaning. Return only the rephrased text.",
            ),
            ImeChip("emojis", "😊 Emojis", "Add emojis in the sentence. Keep the original language. Return only the rewritten text."),
            ImeChip("realistic", "📱 Realistic", "Rewrite this realistically, as if it was quickly typed on a mobile keyboard. Keep the original language. Return only the rewritten text."),
        )
        return builtIn
    }

    fun toneChips(config: NativeDictationConfig?): List<ImeChip> {
        val keepLang = "Write in the same language as the input. Do not translate. Return only the rewritten text."
        val builtIn = listOf(
            ImeChip("funny", "😂 Funny", "Rewrite in a funny tone. $keepLang"),
            ImeChip(
                "poetic",
                "✨ Poetic",
                "Rewrite in a poetic tone in the same language as the input. " +
                    "Do not switch to English or any other language. Do not translate. " +
                    "Return only the rewritten text.",
            ),
            ImeChip("shorten", "✂️ Shorten", "Shorten the text while keeping meaning. $keepLang"),
            ImeChip("sarcastic", "😏 Sarcastic", "Rewrite in a sarcastic tone. $keepLang"),
            ImeChip("angry", "😠 Angry", "Rewrite in an angry tone. $keepLang"),
            ImeChip("flirty", "😘 Flirty", "Rewrite in a flirty tone. $keepLang"),
            ImeChip("genz", "😎 Gen-Z", "Rewrite in a Gen-Z tone. $keepLang"),
            ImeChip("witty", "🧠 Witty", "Rewrite in a witty tone. $keepLang"),
            ImeChip("humanise", "🌿 Humanize", "Humanise this text so it sounds natural and less robotic. $keepLang"),
            ImeChip("idioms", "🗣️ Idioms", "Rewrite using fitting idioms where natural. $keepLang"),
        )
        val customTones = config?.customTones.orEmpty().mapIndexed { index, entry ->
            entry.toChip("tone_custom_$index")
        }
        return builtIn + customTones
    }

    fun chipsFor(kind: ImeSheetKind, config: NativeDictationConfig?): List<ImeChip> {
        return when (kind) {
            ImeSheetKind.Grammar -> grammarChips(config)
            ImeSheetKind.Tone -> toneChips(config)
            else -> emptyList()
        }
    }

    fun isToolbarToolSelected(activeSheet: ImeSheetKind?, tool: ImeSheetKind): Boolean {
        return activeSheet == tool
    }

    /** Tone/Translate tap opens and runs. Grammar tap only opens; long-press runs. */
    fun shouldAutoRunOnToolbarTap(kind: ImeSheetKind): Boolean {
        return kind == ImeSheetKind.Tone || kind == ImeSheetKind.Translate
    }

    fun sheetTitle(kind: ImeSheetKind): String {
        return when (kind) {
            ImeSheetKind.Grammar -> "Rewrite"
            ImeSheetKind.Tone -> "Tone"
            ImeSheetKind.Translate -> "Translate"
            else -> ""
        }
    }

    fun toolbarIcon(kind: ImeSheetKind): String {
        return when (kind) {
            ImeSheetKind.Grammar -> "✍️"
            ImeSheetKind.Tone -> "🎭"
            ImeSheetKind.Translate -> "文A"
            ImeSheetKind.Emoji -> "☺"
            ImeSheetKind.Clipboard -> "📋"
            else -> ""
        }
    }

    fun toolbarIconRes(kind: ImeSheetKind): Int? {
        return when (kind) {
            ImeSheetKind.Grammar -> R.drawable.ic_ime_rewrite
            ImeSheetKind.Tone -> R.drawable.ic_ime_tone
            else -> null
        }
    }

    fun clipboardHint(chip: ImeChip?): String? {
        if (chip?.usesClipboard != true) return null
        return "This replies to the clipboard, not the field. Copy the message, then tap ↻."
    }

    fun translatePrompt(targetLanguageLabel: String): String {
        return "Translate the following text to $targetLanguageLabel. Keep tone and meaning. Return only the translated text."
    }

    fun systemPromptFor(kind: ImeSheetKind): String {
        return when (kind) {
            ImeSheetKind.Grammar -> "You are a precise writing assistant for mobile keyboard text. Output only the final text."
            ImeSheetKind.Tone -> "You rewrite mobile keyboard text into the requested tone. Always keep the input language. Never translate unless explicitly asked. Output only the final text. Never mention OpenAI, ChatGPT, or brand names."
            ImeSheetKind.Translate -> "You are a precise translation engine. Output only the translated text."
            else -> "You rewrite text. Output only the final text."
        }
    }

    private fun CustomPromptEntry.toChip(id: String): ImeChip {
        return ImeChip(id = id, label = name, prompt = prompt)
    }
}
