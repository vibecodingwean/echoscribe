package com.echoscribe.app.ime

import org.junit.Assert.assertEquals
import org.junit.Test

class ImeClipboardStoreTest {
    @Test
    fun capHistoryKeepsOnlyFive() {
        val items = listOf("a", "b", "c", "d", "e", "f", "g")
        assertEquals(listOf("a", "b", "c", "d", "e"), ImeClipboardStore.capHistory(items))
        assertEquals(5, ImeClipboardStore.MAX_ITEMS)
        assertEquals(emptyList<String>(), ImeClipboardStore.capHistory(items, maxItems = 0))
        assertEquals(listOf("a"), ImeClipboardStore.capHistory(items, maxItems = 1))
    }
}
