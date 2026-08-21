package com.echoscribe.app.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ImeAiActionsTest {
    @Test
    fun toolbarHighlightsOnlyTheOpenAiTool() {
        assertTrue(ImeAiActions.isToolbarToolSelected(ImeSheetKind.Grammar, ImeSheetKind.Grammar))
        assertFalse(ImeAiActions.isToolbarToolSelected(ImeSheetKind.Tone, ImeSheetKind.Grammar))
        assertFalse(ImeAiActions.isToolbarToolSelected(null, ImeSheetKind.Grammar))
        assertTrue(ImeAiActions.isToolbarToolSelected(ImeSheetKind.Translate, ImeSheetKind.Translate))
    }

    @Test
    fun grammarTabOwnsReplyFromClipboardAndDropsFree() {
        val chips = ImeAiActions.grammarChips(null)
        assertEquals("reply", chips.last().id)
        assertTrue(chips.last().usesClipboard)
        assertFalse(chips.any { it.id == "free" })
        assertFalse(chips.any { it.id == "humanise" })
        assertFalse(chips.any { it.id == "idioms" })
    }

    @Test
    fun toneTabOwnsHumanizeAndIdioms() {
        val ids = ImeAiActions.toneChips(null).map { it.id }
        assertTrue(ids.contains("humanise"))
        assertTrue(ids.contains("idioms"))
        assertFalse(ids.contains("reply"))
        assertFalse(ids.contains("free"))
        assertFalse(ImeAiActions.toneChips(null).any { it.usesClipboard })
    }

    @Test
    fun assistSheetIsGone() {
        val kinds = ImeSheetKind.values().map { it.name }
        assertFalse(kinds.contains("Assist"))
        assertTrue(kinds.contains("Grammar"))
        assertTrue(kinds.contains("Tone"))
    }

    @Test
    fun rewriteTabTitleAndIcons() {
        assertEquals("Rewrite", ImeAiActions.sheetTitle(ImeSheetKind.Grammar))
        assertEquals("Tone", ImeAiActions.sheetTitle(ImeSheetKind.Tone))
        assertEquals("✍️", ImeAiActions.toolbarIcon(ImeSheetKind.Grammar))
        assertEquals("🎭", ImeAiActions.toolbarIcon(ImeSheetKind.Tone))
        assertEquals("文A", ImeAiActions.toolbarIcon(ImeSheetKind.Translate))
    }

    @Test
    fun rephraseKeepsSourceLanguage() {
        val prompt = ImeAiActions.grammarChips(null).first { it.id == "rephrase" }.prompt
        assertTrue(prompt.contains("same language"))
        assertTrue(prompt.contains("Do not translate"))
    }

    @Test
    fun replyHintMentionsClipboardAndRegenerate() {
        val reply = ImeAiActions.grammarChips(null).first { it.id == "reply" }
        assertTrue(reply.usesClipboard)
        assertTrue(reply.prompt.contains("clipboard"))
        val hint = ImeAiActions.clipboardHint(reply)
        assertTrue(hint!!.contains("clipboard"))
        assertTrue(hint.contains("↻"))
    }
}
