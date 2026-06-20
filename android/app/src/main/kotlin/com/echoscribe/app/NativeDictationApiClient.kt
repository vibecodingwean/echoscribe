package com.echoscribe.app

import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

class NativeDictationApiClient(private val config: NativeDictationConfig) {
    private companion object {
        const val DEFAULT_LOCAL_AI_FORMATTING_MODEL = "qwen2.5:7b"
    }

    fun preflightLocalAi() {
        if (config.provider != "localAi") return
        preflightLocalAiWhisper()
        preflightLocalAiLlm()
    }

    fun transcribe(file: File): String {
        return when (config.provider) {
            "openai" -> transcribeOpenAi(file)
            "gemini" -> transcribeGemini(file)
            "xai" -> transcribeXai(file)
            "localAi" -> transcribeLocalAi(file)
            else -> throw IllegalStateException("Speech input not supported for ${config.brandName.ifBlank { "this provider" }}")
        }
    }

    fun format(rawText: String): String {
        val raw = rawText.trim()
        if (raw.isBlank()) return raw
        return when (config.provider) {
            "openai" -> formatChat(
                endpoint = "https://api.openai.com/v1/chat/completions",
                includeReasoning = false,
                rawText = raw,
            )
            "gemini" -> formatGemini(raw)
            "xai" -> formatChat(
                endpoint = "https://api.x.ai/v1/chat/completions",
                includeReasoning = true,
                rawText = raw,
            )
            "localAi" -> formatLocalAi(raw)
            else -> throw IllegalStateException("Speech input not supported for ${config.brandName.ifBlank { "this provider" }}")
        }
    }

    private fun transcribeOpenAi(file: File): String {
        val json = postMultipart(
            endpoint = "https://api.openai.com/v1/audio/transcriptions",
            headers = mapOf("Authorization" to "Bearer ${config.apiKey}"),
            fields = linkedMapOf(
                "model" to config.transcriptionModel.ifBlank { "gpt-4o-mini-transcribe" },
                "response_format" to "json",
            ),
            fileField = "file",
            file = file,
        )
        return json.optString("text").trim().ifBlank {
            throw IllegalStateException("Transcription returned empty text")
        }
    }

    private fun transcribeXai(file: File): String {
        val json = postMultipart(
            endpoint = "https://api.x.ai/v1/stt",
            headers = mapOf("Authorization" to "Bearer ${config.apiKey}"),
            fields = linkedMapOf("format" to "false"),
            fileField = "file",
            file = file,
        )
        return json.optString("text").trim().ifBlank {
            throw IllegalStateException("Transcription returned empty text")
        }
    }

    private fun transcribeLocalAi(file: File): String {
        val fields = linkedMapOf(
            "model" to config.transcriptionModel.ifBlank { "whisper-1" },
            "response_format" to "json",
        )
        if (config.targetLanguageCode.isNotBlank() && config.targetLanguageCode != "auto") {
            fields["language"] = config.targetLanguageCode
        }
        val json = postMultipart(
            endpoint = config.localAiWhisperUrl.ifBlank {
                throw IllegalStateException("Local AI Whisper URL is not configured")
            },
            headers = emptyMap(),
            fields = fields,
            fileField = "file",
            file = file,
        )
        return json.optString("text").trim().ifBlank {
            throw IllegalStateException("Transcription returned empty text")
        }
    }

    private fun preflightLocalAiWhisper() {
        val endpoint = config.localAiWhisperUrl.ifBlank {
            throw IllegalStateException("Local AI Whisper URL is not configured")
        }
        val health = originEndpoint(endpoint, "/health")
        try {
            requestStatus(health, "GET", 1_500, 1_500, allowClientError = false)
            return
        } catch (e: Exception) {
            if (e.message?.contains("404") != true && e.message?.contains("405") != true) {
                throw e
            }
        }
        requestStatus(endpoint, "HEAD", 1_500, 1_500, allowClientError = true)
    }

    private fun preflightLocalAiLlm() {
        val endpoint = config.localAiLlmUrl.ifBlank {
            throw IllegalStateException("Local AI LLM URL is not configured")
        }
        val model = config.formattingModel.ifBlank { DEFAULT_LOCAL_AI_FORMATTING_MODEL }
        val body = requestText(
            endpoint = originEndpoint(endpoint, "/api/tags"),
            method = "GET",
            connectTimeoutMs = 1_500,
            readTimeoutMs = 1_500,
        )
        if (!ollamaModelExists(body, model)) {
            throw IllegalStateException("Local AI model \"$model\" was not found in Ollama. Pull it or change the model.")
        }
    }

    private fun transcribeGemini(file: File): String {
        val upload = postBytes(
            endpoint = "https://generativelanguage.googleapis.com/upload/v1beta/files?key=${config.apiKey}",
            headers = mapOf(
                "Content-Type" to mimeType(file),
                "X-Goog-Upload-Protocol" to "raw",
                "X-Goog-Upload-File-Name" to file.name,
            ),
            bytes = file.readBytes(),
        )
        val fileObject = upload.optJSONObject("file") ?: upload
        val fileUri = fileObject.optString("uri").ifBlank {
            val name = fileObject.optString("name")
            if (name.isBlank()) {
                throw IllegalStateException("Gemini upload returned no file URI")
            }
            "https://generativelanguage.googleapis.com/v1beta/$name"
        }

        val parts = JSONArray()
            .put(JSONObject().put("text", "Transcribe the following audio accurately. Auto-detect the spoken language and return only the raw transcript text without any extra words."))
            .put(
                JSONObject().put(
                    "fileData",
                    JSONObject()
                        .put("fileUri", fileUri)
                        .put("mimeType", mimeType(file)),
                ),
            )
        val body = JSONObject()
            .put(
                "contents",
                JSONArray().put(
                    JSONObject()
                        .put("role", "user")
                        .put("parts", parts),
                ),
            )
        val json = postJson(
            endpoint = "https://generativelanguage.googleapis.com/v1beta/models/${config.transcriptionModel.ifBlank { "gemini-3.5-flash" }}:generateContent?key=${config.apiKey}",
            headers = mapOf("Content-Type" to "application/json"),
            body = body,
        )
        return extractGeminiText(json).ifBlank {
            throw IllegalStateException("Transcription returned empty text")
        }
    }

    private fun formatChat(endpoint: String, includeReasoning: Boolean, rawText: String): String {
        val messages = JSONArray()
            .put(
                JSONObject()
                    .put("role", "system")
                    .put("content", "You format dictated speech transcripts into final text input. Output only the final text."),
            )
            .put(
                JSONObject()
                    .put("role", "user")
                    .put("content", "${config.dictationPrompt}\n\nRaw text:\n$rawText"),
            )
        val body = JSONObject()
            .put("model", config.formattingModel)
            .put("messages", messages)
        if (includeReasoning && config.reasoningEffort.isNotBlank()) {
            body.put("reasoning_effort", config.reasoningEffort)
        }
        val json = postJson(
            endpoint = endpoint,
            headers = mapOf(
                "Authorization" to "Bearer ${config.apiKey}",
                "Content-Type" to "application/json",
            ),
            body = body,
        )
        val choices = json.optJSONArray("choices")
        val content = choices
            ?.optJSONObject(0)
            ?.optJSONObject("message")
            ?.optString("content")
            .orEmpty()
            .trim()
        if (content.isBlank()) throw IllegalStateException("Formatting returned empty text")
        return content
    }

    private fun formatLocalAi(rawText: String): String {
        val messages = JSONArray()
            .put(
                JSONObject()
                    .put("role", "system")
                    .put("content", "You format dictated speech transcripts into final text input. Output only the final text."),
            )
            .put(
                JSONObject()
                    .put("role", "user")
                    .put("content", "${config.dictationPrompt}\n\nRaw text:\n$rawText"),
            )
        val body = JSONObject()
            .put("model", config.formattingModel.ifBlank { DEFAULT_LOCAL_AI_FORMATTING_MODEL })
            .put("stream", false)
            .put("think", false)
            .put("messages", messages)
        val json = postJson(
            endpoint = config.localAiLlmUrl.ifBlank {
                throw IllegalStateException("Local AI LLM URL is not configured")
            },
            headers = mapOf("Content-Type" to "application/json"),
            body = body,
        )
        val content = json.optJSONObject("message")
            ?.optString("content")
            .orEmpty()
            .trim()
        if (content.isBlank()) throw IllegalStateException("Formatting returned empty text")
        return content
    }

    private fun formatGemini(rawText: String): String {
        val body = JSONObject()
            .put(
                "contents",
                JSONArray().put(
                    JSONObject()
                        .put("role", "user")
                        .put(
                            "parts",
                            JSONArray().put(
                                JSONObject().put(
                                    "text",
                                    "${config.dictationPrompt}\n\nRaw text:\n$rawText",
                                ),
                            ),
                        ),
                ),
            )
        val json = postJson(
            endpoint = "https://generativelanguage.googleapis.com/v1beta/models/${config.formattingModel}:generateContent?key=${config.apiKey}",
            headers = mapOf("Content-Type" to "application/json"),
            body = body,
        )
        val text = extractGeminiText(json).trim()
        if (text.isBlank()) throw IllegalStateException("Formatting returned empty text")
        return text
    }

    private fun postJson(
        endpoint: String,
        headers: Map<String, String>,
        body: JSONObject,
        connectTimeoutMs: Int = 30_000,
        readTimeoutMs: Int = 120_000,
    ): JSONObject {
        val bytes = body.toString().toByteArray(Charsets.UTF_8)
        return requestJson(endpoint, "POST", headers, bytes, connectTimeoutMs, readTimeoutMs)
    }

    private fun postBytes(endpoint: String, headers: Map<String, String>, bytes: ByteArray): JSONObject {
        return requestJson(endpoint, "POST", headers, bytes, 30_000, 120_000)
    }

    private fun requestJson(
        endpoint: String,
        method: String,
        headers: Map<String, String>,
        bytes: ByteArray,
        connectTimeoutMs: Int,
        readTimeoutMs: Int,
    ): JSONObject {
        val connection = (URL(endpoint).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = connectTimeoutMs
            readTimeout = readTimeoutMs
            doOutput = true
            headers.forEach { (key, value) -> setRequestProperty(key, value) }
        }
        connection.outputStream.use { it.write(bytes) }
        return readJson(connection)
    }

    private fun requestText(
        endpoint: String,
        method: String,
        connectTimeoutMs: Int,
        readTimeoutMs: Int,
    ): String {
        val connection = (URL(endpoint).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = connectTimeoutMs
            readTimeout = readTimeoutMs
            doOutput = false
        }
        val status = connection.responseCode
        val stream = if (status in 200..299) connection.inputStream else connection.errorStream
        val body = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()
        if (status !in 200..299) {
            throw IllegalStateException(apiErrorMessage(body).ifBlank { "Request failed ($status)" })
        }
        return body
    }

    private fun requestStatus(
        endpoint: String,
        method: String,
        connectTimeoutMs: Int,
        readTimeoutMs: Int,
        allowClientError: Boolean,
    ) {
        val connection = (URL(endpoint).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = connectTimeoutMs
            readTimeout = readTimeoutMs
            doOutput = false
        }
        val status = connection.responseCode
        if (status == 401 || status == 403 || status >= 500 || (!allowClientError && status !in 200..299)) {
            throw IllegalStateException("Request failed ($status)")
        }
    }

    private fun postMultipart(
        endpoint: String,
        headers: Map<String, String>,
        fields: LinkedHashMap<String, String>,
        fileField: String,
        file: File,
        connectTimeoutMs: Int = 30_000,
        readTimeoutMs: Int = 180_000,
    ): JSONObject {
        val boundary = "EchoScribeBoundary${System.currentTimeMillis()}"
        val connection = (URL(endpoint).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = connectTimeoutMs
            readTimeout = readTimeoutMs
            doOutput = true
            setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
            headers.forEach { (key, value) -> setRequestProperty(key, value) }
        }

        BufferedOutputStream(connection.outputStream).use { output ->
            fun write(value: String) = output.write(value.toByteArray(Charsets.UTF_8))
            fields.forEach { (name, value) ->
                write("--$boundary\r\n")
                write("Content-Disposition: form-data; name=\"$name\"\r\n\r\n")
                write("$value\r\n")
            }
            write("--$boundary\r\n")
            write("Content-Disposition: form-data; name=\"$fileField\"; filename=\"${file.name}\"\r\n")
            write("Content-Type: ${mimeType(file)}\r\n\r\n")
            file.inputStream().use { input -> input.copyTo(output) }
            write("\r\n--$boundary--\r\n")
        }
        return readJson(connection)
    }

    private fun readJson(connection: HttpURLConnection): JSONObject {
        val status = connection.responseCode
        val stream = if (status in 200..299) connection.inputStream else connection.errorStream
        val body = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()
        if (status !in 200..299) {
            throw IllegalStateException(apiErrorMessage(body).ifBlank { "Request failed ($status)" })
        }
        return JSONObject(body)
    }

    private fun apiErrorMessage(body: String): String {
        return try {
            val json = JSONObject(body)
            json.optJSONObject("error")?.optString("message")
                ?: json.optString("message")
        } catch (_: Exception) {
            body.take(200)
        }
    }

    private fun extractGeminiText(json: JSONObject): String {
        val candidates = json.optJSONArray("candidates") ?: return ""
        val content = candidates.optJSONObject(0)?.optJSONObject("content") ?: return ""
        val parts = content.optJSONArray("parts") ?: return ""
        return parts.optJSONObject(0)?.optString("text").orEmpty()
    }

    private fun mimeType(file: File): String {
        return when (file.extension.lowercase()) {
            "m4a" -> "audio/m4a"
            "mp3" -> "audio/mpeg"
            "wav" -> "audio/wav"
            "webm" -> "audio/webm"
            "ogg", "oga", "opus" -> "audio/ogg"
            else -> "application/octet-stream"
        }
    }

    private fun originEndpoint(endpoint: String, path: String): String {
        val url = URL(endpoint)
        return URL(url.protocol, url.host, url.port, path).toString()
    }

    private fun ollamaModelExists(body: String, expectedModel: String): Boolean {
        val models = JSONObject(body).optJSONArray("models") ?: return false
        for (index in 0 until models.length()) {
            val item = models.optJSONObject(index) ?: continue
            if (item.optString("name") == expectedModel || item.optString("model") == expectedModel) {
                return true
            }
        }
        return false
    }

}
