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
    fun geminiFormattingRequestOmitsProThinkingButKeepsFastSuppression() {
        for (model in listOf("gemini-3.1-pro-preview", "gemini-3.8-flash")) {
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
            if (model == "gemini-3.8-flash") {
                expected.put("generationConfig", JSONObject().put(
                    "thinkingConfig", JSONObject().put("thinkingBudget", 0),
                ))
            }
            assertEquals(expected.toString(), body.toString())
        }
    }

    @Test
    fun geminiFormattingAndImeRewriteUseSelectedModel() {
        for (model in listOf("gemini-3.1-pro-preview", "gemini-3.8-flash")) {
            val config = xaiConfig("").copy(provider = "gemini", formattingModel = model)
            lateinit var request: CapturingConnection
            val client = NativeDictationApiClient(config) { url ->
                request = CapturingConnection(url)
                request
            }
            for (rewrite in listOf(false, true)) {
                assertThrows(IllegalStateException::class.java) {
                    if (rewrite) client.rewrite("System", "User") else client.format("User")
                }
                assertTrue(request.url.toString().contains("/$model:generateContent"))
                val body = JSONObject(request.body.toString(Charsets.UTF_8.name()))
                assertEquals(model == "gemini-3.8-flash", body.has("generationConfig"))
            }
        }
    }

    @Test
    fun geminiFormattingAndRewriteIgnoreThoughtBeforeFinalText() {
        val response = """{"candidates":[{"content":{"parts":[{"thought":true,"text":"private reasoning"},{"text":"Final text"}]}}]}"""
        val client = NativeDictationApiClient(
            xaiConfig("").copy(provider = "gemini", formattingModel = "gemini-3.1-pro-preview"),
        ) { url -> CapturingConnection(url, 200, response) }

        assertEquals("Final text", client.format("Raw text"))
        assertEquals("Final text", client.rewrite("System", "User"))
    }

    @Test
    fun geminiFormattingAndRewriteRejectThoughtOnlyResponse() {
        val response = """{"candidates":[{"content":{"parts":[{"thought":true,"text":"private reasoning"}]}}]}"""
        val client = NativeDictationApiClient(
            xaiConfig("").copy(provider = "gemini", formattingModel = "gemini-3.1-pro-preview"),
        ) { url -> CapturingConnection(url, 200, response) }

        val formatError = assertThrows(IllegalStateException::class.java) { client.format("Raw text") }
        assertEquals("AI rewrite returned empty text", formatError.message)
        val rewriteError = assertThrows(IllegalStateException::class.java) { client.rewrite("System", "User") }
        assertEquals("AI rewrite returned empty text", rewriteError.message)
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
            val client = NativeDictationApiClient(xaiConfig(configModel)) { url ->
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
