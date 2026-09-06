package com.echoscribe.app.ime

import com.echoscribe.app.R
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
        assertEquals("reply", chips[1].id)
        assertTrue(chips[1].usesClipboard)
        assertEquals("grammar_fix", chips[0].id)
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
        assertEquals(R.drawable.ic_ime_rewrite, ImeAiActions.toolbarIconRes(ImeSheetKind.Grammar))
        assertEquals(R.drawable.ic_ime_tone, ImeAiActions.toolbarIconRes(ImeSheetKind.Tone))
        assertEquals(null, ImeAiActions.toolbarIconRes(ImeSheetKind.Translate))
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

    @Test
    fun grammarTapDoesNotAutoRunButToneDoes() {
        assertFalse(ImeAiActions.shouldAutoRunOnToolbarTap(ImeSheetKind.Grammar))
        assertTrue(ImeAiActions.shouldAutoRunOnToolbarTap(ImeSheetKind.Tone))
        assertTrue(ImeAiActions.shouldAutoRunOnToolbarTap(ImeSheetKind.Translate))
    }

    @Test
    fun poeticAndToneKeepSourceLanguage() {
        val poetic = ImeAiActions.toneChips(null).first { it.id == "poetic" }.prompt
        assertTrue(poetic.contains("same language"))
        assertTrue(poetic.contains("Do not translate"))
        assertTrue(poetic.contains("Do not switch to English"))
        val system = ImeAiActions.systemPromptFor(ImeSheetKind.Tone)
        assertTrue(system.contains("keep the input language"))
        ImeAiActions.toneChips(null).forEach { chip ->
            assertTrue(chip.id, chip.prompt.contains("Do not translate"))
        }
    }
}
