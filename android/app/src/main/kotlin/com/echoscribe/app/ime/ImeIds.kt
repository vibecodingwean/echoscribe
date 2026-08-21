package com.echoscribe.app.ime

object ImeIds {
    const val SERVICE_CLASS = "com.echoscribe.app.ime.EchoScribeImeService"
    const val SERVICE_SHORT = ".ime.EchoScribeImeService"

    fun matches(packageName: String, imeId: String): Boolean {
        val id = imeId.trim()
        if (id.isEmpty()) return false
        val candidates = listOf(
            "$packageName/$SERVICE_CLASS",
            "$packageName/$SERVICE_SHORT",
        )
        return candidates.any { it.equals(id, ignoreCase = true) }
    }
}
