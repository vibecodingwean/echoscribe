package com.echoscribe.app.ime

import com.echoscribe.app.CustomPromptEntry
import com.echoscribe.app.NativeDictationConfig

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
                "rephrase",
                "🔄 Rephrase",
                "Rephrase this text in the same language as the input. Do not translate. Keep meaning. Return only the rephrased text.",
            ),
            ImeChip("emojis", "😊 Emojis", "Add emojis in the sentence. Keep the original language. Return only the rewritten text."),
            ImeChip("realistic", "📱 Realistic", "Rewrite this realistically, as if it was quickly typed on a mobile keyboard. Keep the original language. Return only the rewritten text."),
            ImeChip(
                "reply",
                "💬 Reply",
                "The text below is a copied message from the clipboard, not the input field. Write a concise, natural reply to that copied message. Keep the same language. Return only the reply.",
                usesClipboard = true,
            ),
        )
        return builtIn
    }

    fun toneChips(config: NativeDictationConfig?): List<ImeChip> {
        val builtIn = listOf(
            ImeChip("funny", "😂 Funny", "Rewrite in a funny tone. Keep language. Return only the rewritten text."),
            ImeChip("poetic", "✨ Poetic", "Rewrite in a poetic tone. Keep language. Return only the rewritten text."),
            ImeChip("shorten", "✂️ Shorten", "Shorten the text while keeping meaning. Return only the shortened text."),
            ImeChip("sarcastic", "😏 Sarcastic", "Rewrite in a sarcastic tone. Keep language. Return only the rewritten text."),
            ImeChip("angry", "😠 Angry", "Rewrite in an angry tone. Keep language. Return only the rewritten text."),
            ImeChip("flirty", "😘 Flirty", "Rewrite in a flirty tone. Keep language. Return only the rewritten text."),
            ImeChip("genz", "😎 Gen-Z", "Rewrite in a Gen-Z tone. Keep language. Return only the rewritten text."),
            ImeChip("witty", "🧠 Witty", "Rewrite in a witty tone. Keep language. Return only the rewritten text."),
            ImeChip("humanise", "🌿 Humanize", "Humanise this text so it sounds natural and less robotic. Keep language. Return only the rewritten text."),
            ImeChip("idioms", "🗣️ Idioms", "Rewrite using fitting idioms where natural. Keep language. Return only the rewritten text."),
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
            ImeSheetKind.Tone -> "You rewrite mobile keyboard text into the requested tone. Output only the final text. Never mention OpenAI, ChatGPT, or brand names."
            ImeSheetKind.Translate -> "You are a precise translation engine. Output only the translated text."
            else -> "You rewrite text. Output only the final text."
        }
    }

    private fun CustomPromptEntry.toChip(id: String): ImeChip {
        return ImeChip(id = id, label = name, prompt = prompt)
    }
}
