package com.echoscribe.app

import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

class NativeDictationApiClient(private val config: NativeDictationConfig) {
    fun transcribe(file: File): String {
        return when (config.provider) {
            "openai" -> transcribeOpenAi(file)
            "gemini" -> transcribeGemini(file)
            "xai" -> transcribeXai(file)
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
            endpoint = "https://generativelanguage.googleapis.com/v1beta/models/${config.transcriptionModel.ifBlank { "gemini-3.1-flash-lite" }}:generateContent?key=${config.apiKey}",
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

    private fun postJson(endpoint: String, headers: Map<String, String>, body: JSONObject): JSONObject {
        val bytes = body.toString().toByteArray(Charsets.UTF_8)
        return requestJson(endpoint, "POST", headers, bytes)
    }

    private fun postBytes(endpoint: String, headers: Map<String, String>, bytes: ByteArray): JSONObject {
        return requestJson(endpoint, "POST", headers, bytes)
    }

    private fun requestJson(
        endpoint: String,
        method: String,
        headers: Map<String, String>,
        bytes: ByteArray,
    ): JSONObject {
        val connection = (URL(endpoint).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = 30_000
            readTimeout = 120_000
            doOutput = true
            headers.forEach { (key, value) -> setRequestProperty(key, value) }
        }
        connection.outputStream.use { it.write(bytes) }
        return readJson(connection)
    }

    private fun postMultipart(
        endpoint: String,
        headers: Map<String, String>,
        fields: LinkedHashMap<String, String>,
        fileField: String,
        file: File,
    ): JSONObject {
        val boundary = "EchoScribeBoundary${System.currentTimeMillis()}"
        val connection = (URL(endpoint).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 30_000
            readTimeout = 180_000
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
}
