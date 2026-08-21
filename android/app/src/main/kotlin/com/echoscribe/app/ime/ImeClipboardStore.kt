package com.echoscribe.app.ime

import android.content.Context
import org.json.JSONArray

/** Local-only clipboard history for the IME. No network. */
class ImeClipboardStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun add(text: String) {
        val trimmed = text.trim().take(MAX_CHARS)
        if (trimmed.isEmpty()) return
        val next = (listOf(trimmed) + load().filterNot { it == trimmed }).take(MAX_ITEMS)
        val array = JSONArray()
        next.forEach { array.put(it) }
        prefs.edit().putString(KEY, array.toString()).apply()
    }

    fun load(): List<String> {
        val raw = prefs.getString(KEY, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            buildList {
                for (i in 0 until array.length()) {
                    val value = array.optString(i).trim()
                    if (value.isNotEmpty()) add(value)
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun clear() {
        prefs.edit().remove(KEY).apply()
    }

    companion object {
        private const val PREFS = "echoscribe_ime_clipboard"
        private const val KEY = "items"
        private const val MAX_ITEMS = 20
        private const val MAX_CHARS = 32_000
    }
}
