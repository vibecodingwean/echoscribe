package com.echoscribe.app

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.assertThrows
import org.junit.Test

class NativeDictationApiClientTest {
    @Test
    fun nativeRequestsRequireTheMatchingDataPermissionBeforeOpeningConnection() {
        var connections = 0
        val config = xaiConfig("").copy(provider = "gemini", formattingModel = "gemini-3.8-flash")
        val client = NativeDictationApiClient(
            config,
            consentCheck = { use -> use == "fileAudio" },
        ) { url ->
            connections++
            CapturingConnection(url)
        }
        val error = assertThrows(IllegalStateException::class.java) {
            client.rewrite("System", "private text")
        }
        assertTrue(error.message!!.contains("allow AI sharing"))
        assertEquals(0, connections)
    }

    @Test
    fun geminiFormattingRequestUsesArgonConfigButKeepsLegacyAndFastContract() {
        for (model in listOf("gemini-4-argon", "gemini-3.1-pro-preview", "gemini-3.8-flash")) {
            val body = NativeDictationApiClient.buildGeminiFormattingRequest(model, "System", "User")
            val expected = JSONObject().put(
                "systemInstruction",
                JSONObject().put("parts", org.json.JSONArray().put(JSONObject().put("text", "System"))),
            ).put(
                "contents",
                org.json.JSONArray().put(JSONObject().put("role", "user").put(
                    "parts", org.json.JSONArray().put(JSONObject().put("text", "User")),
                )),
            )
            if (model == "gemini-4-argon") {
                expected.put("generationConfig", JSONObject().put("maxOutputTokens", 32768).put(
                    "thinkingConfig", JSONObject().put("thinkingLevel", "low"),
                ))
            } else if (model == "gemini-3.8-flash") {
                expected.put("generationConfig", JSONObject().put(
                    "thinkingConfig", JSONObject().put("thinkingBudget", 0),
                ))
            }
            assertEquals(expected.toString(), body.toString())
        }
    }

    @Test
    fun geminiFormattingAndImeRewriteUseSelectedModel() {
        for (model in listOf("gemini-4-argon", "gemini-3.1-pro-preview", "gemini-3.8-flash", "custom-gemini-model")) {
            val config = xaiConfig("").copy(provider = "gemini", formattingModel = model)
            lateinit var request: CapturingConnection
            val client = NativeDictationApiClient(config, consentCheck = { _ -> true }) { url ->
                request = CapturingConnection(url)
                request
            }
            for (rewrite in listOf(false, true)) {
                assertThrows(IllegalStateException::class.java) {
                    if (rewrite) client.rewrite("System", "User") else client.format("User")
                }
                val effective = if (model == "gemini-3.1-pro-preview") "gemini-4-argon" else model
                assertTrue(request.url.toString().contains("/$effective:generateContent"))
                val body = JSONObject(request.body.toString(Charsets.UTF_8.name()))
                assertTrue(body.has("generationConfig"))
            }
        }
    }

    @Test
    fun geminiFormattingAndRewriteIgnoreThoughtBeforeFinalText() {
        val response = """{"candidates":[{"finishReason":"STOP","content":{"parts":[{"thought":true,"text":"private reasoning"},{"text":"Final text"}]}}]}"""
        val client = NativeDictationApiClient(
            xaiConfig("").copy(provider = "gemini", formattingModel = "gemini-3.1-pro-preview"),
            consentCheck = { _ -> true },
        ) { url -> CapturingConnection(url, 200, response) }

        assertEquals("Final text", client.format("Raw text"))
        assertEquals("Final text", client.rewrite("System", "User"))
    }

    @Test
    fun geminiFormattingAndRewriteRejectThoughtOnlyResponse() {
        val response = """{"candidates":[{"finishReason":"STOP","content":{"parts":[{"thought":true,"text":"private reasoning"}]}}]}"""
        val client = NativeDictationApiClient(
            xaiConfig("").copy(provider = "gemini", formattingModel = "gemini-3.1-pro-preview"),
            consentCheck = { _ -> true },
        ) { url -> CapturingConnection(url, 200, response) }

        val formatError = assertThrows(IllegalStateException::class.java) { client.format("Raw text") }
        assertEquals("AI rewrite returned empty text", formatError.message)
        val rewriteError = assertThrows(IllegalStateException::class.java) { client.rewrite("System", "User") }
        assertEquals("AI rewrite returned empty text", rewriteError.message)
    }

    @Test
    fun argonFormattingKeepsAllVisiblePartsWhileLegacyExtractionIsUnchanged() {
        val response = """{"candidates":[{"finishReason":"STOP","content":{"parts":[{"thought":true,"text":"Reasoning"},{"text":"First"},{"text":"Second"}]}}]}"""
        for ((model, expected) in mapOf("gemini-4-argon" to "First\nSecond", "gemini-3.8-flash" to "First")) {
            val client = NativeDictationApiClient(
                xaiConfig("").copy(provider = "gemini", formattingModel = model),
            consentCheck = { _ -> true },
            ) { url -> CapturingConnection(url, 200, response) }
            assertEquals(expected, client.format("Raw text"))
            assertEquals(expected, client.rewrite("System", "User"))
        }
    }

    @Test
    fun argonFormattingRejectsTruncationAndMissingCompletionEvenWithVisibleText() {
        for (reason in listOf("MAX_TOKENS", "SAFETY", "")) {
            val response = """{"candidates":[{"finishReason":"$reason","content":{"parts":[{"text":"Incomplete"}]}}]}"""
            val client = NativeDictationApiClient(
                xaiConfig("").copy(provider = "gemini", formattingModel = "gemini-4-argon"),
            consentCheck = { _ -> true },
            ) { url -> CapturingConnection(url, 200, response) }
            assertThrows(IllegalStateException::class.java) { client.format("Raw text") }
            assertThrows(IllegalStateException::class.java) { client.rewrite("System", "User") }
        }
    }

    @Test
    fun retainedNativeFormattingMigratesOnlyExactOldPro() {
        for ((saved, expected) in mapOf("" to "gemini-3.8-flash", "gemini-3.1-pro-preview" to "gemini-4-argon",
            "gemini-3.8-flash" to "gemini-3.8-flash", "my-custom-model" to "my-custom-model",
            "gemini-3.1-pro-preview-custom" to "gemini-3.1-pro-preview-custom")) {
            assertEquals(expected, NativeDictationApiClient.effectiveGeminiFormattingModel(saved))
        }
    }

    @Test
    fun xaiMultipartRequestIncludesSelectedModel() {
        assertXaiMultipartModel("selected-xai-model", "selected-xai-model")
    }

    @Test
    fun xaiMultipartRequestUsesCurrentModelWhenNativeConfigIsBlank() {
        assertXaiMultipartModel("", "grok-voice-transcribe-2.0")
    }

    @Test
    fun xaiMultipartRequestMigratesPersistedLegacyModel() {
        assertXaiMultipartModel("xai-stt", "grok-voice-transcribe-2.0")
    }

    private fun assertXaiMultipartModel(configModel: String, expectedModel: String) {
        val audio = File.createTempFile("echoscribe-native-stt-", ".m4a")
        try {
            audio.writeBytes(byteArrayOf(1, 2, 3))
            lateinit var request: CapturingConnection
            val client = NativeDictationApiClient(xaiConfig(configModel), consentCheck = { _ -> true }) { url ->
                request = CapturingConnection(url)
                request
            }
            assertThrows(IllegalStateException::class.java) { client.transcribe(audio) }

            assertEquals("https://api.x.ai/v1/stt", request.url.toString())
            assertEquals("POST", request.requestMethod)
            assertEquals("Bearer unit-test-key", request.getRequestProperty("Authorization"))
            val body = request.body.toString(Charsets.UTF_8.name())
            assertTrue(body.contains("name=\"model\"\r\n\r\n$expectedModel\r\n"))
            assertTrue(body.contains("name=\"format\"\r\n\r\nfalse\r\n"))
            assertTrue(body.contains("name=\"file\"; filename=\"${audio.name}\""))
        } finally {
            audio.delete()
        }
    }

    private fun xaiConfig(model: String) = NativeDictationConfig(
        enabled = true,
        floatingEnabled = false,
        provider = "xai",
        brandName = "Grok",
        apiKey = "unit-test-key",
        targetLanguageCode = "auto",
        dictationPrompt = "",
        transcriptionModel = model,
        formattingModel = "",
        reasoningEffort = "none",
        supportsDictation = true,
        localAiLlmUrl = "",
        localAiWhisperUrl = "",
    )

    private class CapturingConnection(
        url: URL,
        private val status: Int = 400,
        private val response: String = "",
    ) : HttpURLConnection(url) {
        val body = ByteArrayOutputStream()

        override fun connect() = Unit
        override fun disconnect() = Unit
        override fun usingProxy() = false
        override fun getOutputStream() = body
        override fun getResponseCode() = status
        override fun getInputStream(): InputStream = ByteArrayInputStream(response.toByteArray())
        override fun getErrorStream(): InputStream = ByteArrayInputStream("synthetic error".toByteArray())
    }
}
