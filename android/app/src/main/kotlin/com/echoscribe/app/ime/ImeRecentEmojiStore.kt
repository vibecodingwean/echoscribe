package com.echoscribe.app.ime

import android.content.Context
import org.json.JSONArray

/** Local-only recently used emojis for the IME. No network. */
class ImeRecentEmojiStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun add(emoji: String) {
        val value = emoji.trim()
        if (value.isEmpty()) return
        val next = (listOf(value) + load().filterNot { it == value }).take(MAX_ITEMS)
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

    companion object {
        private const val PREFS = "echoscribe_ime_recent_emoji"
        private const val KEY = "items"
        private const val MAX_ITEMS = 16
    }
}
