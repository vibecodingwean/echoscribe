import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:echoscribe/services/debug_console.dart';
import 'package:echoscribe/config/prompts.dart';
import 'package:echoscribe/models/app_exception.dart';
import 'package:echoscribe/services/speakers/native_speaker_formatter.dart';
import 'package:echoscribe/services/speakers/speaker_aware_summary.dart';
import 'package:echoscribe/services/speakers/speaker_models.dart';

class GeminiService {
  static const String _uploadEndpoint =
      'https://generativelanguage.googleapis.com/upload/v1beta/files';
  static const String _modelsEndpoint =
      'https://generativelanguage.googleapis.com/v1beta/models';
  static const String _interactionsEndpoint =
      'https://generativelanguage.googleapis.com/v1beta/interactions';
  static const int _inlineFallbackMaxBytes = 15 * 1024 * 1024;

  /// Interactions API body for `gemini-3.5-transcribe`.
  /// Official field is `language_codes` (omit/empty = auto). Never `language_hints`.
  static Map<String, dynamic> buildDedicatedTranscriptionRequest({
    required String model,
    required Map<String, dynamic> audioInput,
    List<String>? languageCodes,
  }) {
    final transcriptionConfig = <String, dynamic>{
      'mode': {
        'type': 'verbatim',
        'diarization_mode': 'speaker',
      },
    };
    if (languageCodes != null && languageCodes.isNotEmpty) {
      transcriptionConfig['language_codes'] = languageCodes;
    }
    return {
      'model': model,
      'input': [audioInput],
      'generation_config': {
        'transcription_config': transcriptionConfig,
      },
    };
  }

  // Upload audio bytes as raw media (no base64) using the official upload endpoint,
  // then request transcription with Gemini. Supports files larger than 20MB.
  Future<String> transcribe({
    required String apiKey,
    String? filePath,
    List<int>? fileBytes,
    String fileName = 'audio.m4a',
    String mimeType = 'audio/m4a',
    String model = AiModelConfig.geminiTranscriptionFast,
  }) async {
    if ((filePath == null || filePath.isEmpty) &&
        (fileBytes == null || fileBytes.isEmpty)) {
      throw Exception('No audio file provided');
    }

    final bytes = fileBytes ?? await File(filePath!).readAsBytes();

    if (isGeminiDedicatedTranscribeModel(model)) {
      final labeled = await transcribeDedicated(
        apiKey: apiKey,
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        model: model,
      );
      return labeled.text;
    }

    // Fallback: generateContent LLM path for older Gemini transcription models.
    final fileObj = await _uploadFileRaw(
      apiKey: apiKey,
      fileName: fileName,
      mimeType: mimeType,
      bytes: bytes,
    );
    return _transcribeGenerateContent(
      apiKey: apiKey,
      model: model,
      mimeType: mimeType,
      fileUri: fileObj['uri']?.toString() ?? '',
    );
  }

  Future<SpeakerLabeledTranscript> transcribeDedicated({
    required String apiKey,
    required List<int> bytes,
    required String fileName,
    required String mimeType,
    String model = AiModelConfig.geminiTranscriptionFast,
  }) async {
    final fileObj = await _uploadFileRaw(
      apiKey: apiKey,
      fileName: fileName,
      mimeType: mimeType,
      bytes: bytes,
    );
    final fileUri = fileObj['uri']?.toString() ?? '';
    if (fileUri.isEmpty) {
      throw const AppException('Gemini upload returned no file URI');
    }

    try {
      final payload = await _postInteractions(
        apiKey: apiKey,
        model: model,
        mimeType: mimeType,
        fileUri: fileUri,
      );
      return parseInteractionsTranscript(payload);
    } catch (uriError) {
      if (bytes.length > _inlineFallbackMaxBytes) rethrow;
      DebugConsole.log(
        'Gemini Interactions URI path failed; retrying inline for small file: $uriError',
      );
      final payload = await _postInteractions(
        apiKey: apiKey,
        model: model,
        mimeType: mimeType,
        inlineBase64: base64Encode(bytes),
      );
      return parseInteractionsTranscript(payload);
    }
  }

  Future<Map<String, dynamic>> _postInteractions({
    required String apiKey,
    required String model,
    required String mimeType,
    String? fileUri,
    String? inlineBase64,
  }) async {
    final uri = Uri.parse(_interactionsEndpoint);
    final headers = {
      'Content-Type': 'application/json',
      'x-goog-api-key': apiKey,
    };

    final Map<String, dynamic> audioInput;
    if (fileUri != null && fileUri.isNotEmpty) {
      audioInput = {
        'type': 'audio',
        'uri': fileUri,
        'mime_type': mimeType,
      };
    } else if (inlineBase64 != null && inlineBase64.isNotEmpty) {
      audioInput = {
        'type': 'audio',
        'data': inlineBase64,
        'mime_type': mimeType,
      };
    } else {
      throw const AppException('No audio input for Gemini Interactions');
    }

    final body = json.encode(
      buildDedicatedTranscriptionRequest(
        model: model,
        audioInput: audioInput,
      ),
    );

    final sw = Stopwatch()..start();
    DebugConsole.logApiStart(
      method: 'POST',
      url: uri,
      requestBytes: utf8.encode(body).length,
      note: 'Gemini interactions transcribe',
    );
    DebugConsole.logApiRequest(
      method: 'POST',
      url: uri,
      headers: headers,
      body: body,
    );
    final res = await http.post(uri, headers: headers, body: body);
    sw.stop();
    DebugConsole.logApiEnd(
      status: res.statusCode,
      elapsedMs: sw.elapsedMilliseconds,
      responseBytes: res.bodyBytes.length,
    );
    DebugConsole.logApiResponse(
      status: res.statusCode,
      headers: res.headers,
      body: res.body,
      title: 'API response (Gemini interactions)',
    );

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = json.decode(res.body);
      if (data is Map<String, dynamic>) return data;
      throw const AppException('Gemini Interactions returned non-object JSON');
    }

    String? apiMessage;
    try {
      final err = json.decode(res.body) as Map<String, dynamic>;
      final msg = err['error']?['message'];
      if (msg is String && msg.isNotEmpty) apiMessage = msg;
    } catch (_) {}
    throw AppException.fromHttp(
      res.statusCode,
      apiMessage: apiMessage,
      fallback: 'Gemini transcription failed',
    );
  }

  Future<String> _transcribeGenerateContent({
    required String apiKey,
    required String model,
    required String mimeType,
    required String fileUri,
  }) async {
    final uri =
        Uri.parse('$_modelsEndpoint/$model:generateContent?key=$apiKey');
    final headers = {'Content-Type': 'application/json'};
    final body = json.encode({
      'contents': [
        {
          'role': 'user',
          'parts': [
            {
              'text':
                  'Transcribe the following audio accurately. Auto-detect the spoken language and return only the raw transcript text without any extra words.'
            },
            {
              'fileData': {
                'fileUri': fileUri,
                'mimeType': mimeType,
              }
            }
          ]
        }
      ],
      'generationConfig': {
        'thinkingConfig': {
          'thinkingBudget': 0,
        },
      },
    });

    final sw = Stopwatch()..start();
    DebugConsole.logApiStart(
      method: 'POST',
      url: uri,
      requestBytes: utf8.encode(body).length,
      note: 'Gemini generateContent',
    );
    DebugConsole.logApiRequest(
      method: 'POST',
      url: uri,
      headers: headers,
      body: body,
    );
    final res = await http.post(uri, headers: headers, body: body);
    sw.stop();
    DebugConsole.logApiEnd(
      status: res.statusCode,
      elapsedMs: sw.elapsedMilliseconds,
      responseBytes: res.bodyBytes.length,
    );
    DebugConsole.logApiResponse(
      status: res.statusCode,
      headers: res.headers,
      body: res.body,
      title: 'API response (Gemini transcribe)',
    );

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = json.decode(res.body) as Map<String, dynamic>;
      final candidates = data['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) {
        throw const EmptyResultException('No transcription candidates');
      }
      final parts =
          (candidates.first['content']?['parts'] as List<dynamic>?) ?? const [];
      final text = parts
          .whereType<Map>()
          .where((part) => part['thought'] != true)
          .map((part) => (part['text'] ?? '').toString())
          .firstWhere((value) => value.trim().isNotEmpty, orElse: () => '');
      if (text.trim().isEmpty) {
        throw const EmptyResultException('Empty transcription result');
      }
      return text.trim();
    }

    String? apiMessage;
    try {
      final err = json.decode(res.body) as Map<String, dynamic>;
      final msg = err['error']?['message'];
      if (msg is String && msg.isNotEmpty) apiMessage = msg;
    } catch (_) {}
    throw AppException.fromHttp(
      res.statusCode,
      apiMessage: apiMessage,
      fallback: 'Gemini transcription failed',
    );
  }

  /// Parses Interactions API transcription JSON into labeled transcript text.
  static SpeakerLabeledTranscript parseInteractionsTranscript(
    Map<String, dynamic> payload,
  ) {
    final turns = extractSpeakerTurns(payload);
    final plain = extractOutputText(payload);

    if (turns.isNotEmpty) {
      final formatted = NativeSpeakerFormatter.format(turns);
      if (formatted.isNotEmpty) {
        return SpeakerLabeledTranscript(
          text: formatted,
          source: SpeakerSource.nativeApi,
          turns: turns,
        );
      }
    }

    if (plain.trim().isEmpty) {
      throw const EmptyResultException('Empty transcription result');
    }

    final source = SpeakerAwareSummary.hasNativeSpeakerLabels(plain)
        ? SpeakerSource.nativeApi
        : SpeakerSource.none;
    return SpeakerLabeledTranscript(
      text: plain.trim(),
      source: source,
      turns: const [],
    );
  }

  static String extractOutputText(Map<String, dynamic> payload) {
    final outputText = payload['output_text'];
    if (outputText is String && outputText.trim().isNotEmpty) {
      return outputText.trim();
    }

    final texts = <String>[];
    final steps = payload['steps'];
    if (steps is List) {
      for (final step in steps) {
        if (step is! Map) continue;
        final content = step['content'];
        if (content is! List) continue;
        for (final item in content) {
          if (item is! Map) continue;
          final text = item['text'];
          if (text is String && text.trim().isNotEmpty) {
            texts.add(text.trim());
          }
        }
      }
    }

    final outputs = payload['outputs'] ?? payload['output'];
    if (outputs is List) {
      for (final item in outputs) {
        if (item is! Map) continue;
        final text = item['text'];
        if (text is String && text.trim().isNotEmpty) {
          texts.add(text.trim());
        }
      }
    } else if (outputs is Map) {
      final text = outputs['text'];
      if (text is String && text.trim().isNotEmpty) {
        texts.add(text.trim());
      }
    }

    return texts.join('\n').trim();
  }

  static List<SpeakerTurn> extractSpeakerTurns(Map<String, dynamic> payload) {
    final words = <_WordAnno>[];

    void collectFromAnnotations(dynamic annotations) {
      if (annotations is! List) return;
      for (final annotation in annotations) {
        if (annotation is! Map) continue;
        final type = (annotation['type'] ?? '').toString().toLowerCase();
        if (type.isNotEmpty && type != 'word_info' && type != 'word') continue;
        final text = (annotation['text'] ?? annotation['word'] ?? '')
            .toString()
            .trim();
        if (text.isEmpty) continue;
        final speakerRaw = annotation['speaker'];
        if (speakerRaw == null) continue;
        final speaker = speakerRaw.toString().trim();
        if (speaker.isEmpty) continue;
        words.add(
          _WordAnno(
            speaker: speaker,
            text: text,
            startSec: _parseOffsetSeconds(
              annotation['start_offset'] ??
                  annotation['startOffset'] ??
                  annotation['start'],
            ),
          ),
        );
      }
    }

    void walk(dynamic node) {
      if (node is Map) {
        if (node.containsKey('annotations')) {
          collectFromAnnotations(node['annotations']);
          // Annotations already consumed; still walk sibling fields, but skip
          // re-entering the annotations list to avoid duplicate word_info hits.
          for (final entry in node.entries) {
            if (entry.key == 'annotations') continue;
            walk(entry.value);
          }
          return;
        }
        // Some payloads nest word_info objects directly under content.
        final type = (node['type'] ?? '').toString().toLowerCase();
        if (type == 'word_info' || type == 'word') {
          collectFromAnnotations([node]);
          return;
        }
        for (final value in node.values) {
          walk(value);
        }
      } else if (node is List) {
        for (final item in node) {
          walk(item);
        }
      }
    }

    walk(payload);
    if (words.isEmpty) return const [];

    final turns = <SpeakerTurn>[];
    String? currentSpeaker;
    final currentText = StringBuffer();
    double? turnStart;

    void flush() {
      final text = currentText.toString().trim();
      if (currentSpeaker == null || text.isEmpty) return;
      turns.add(
        SpeakerTurn(
          speaker: NativeSpeakerFormatter.normalizeSpeakerLabel(currentSpeaker),
          text: text,
          startSec: turnStart,
        ),
      );
      currentText.clear();
      turnStart = null;
    }

    for (final word in words) {
      final speaker =
          NativeSpeakerFormatter.normalizeSpeakerLabel(word.speaker);
      if (speaker == currentSpeaker) {
        if (currentText.isNotEmpty) currentText.write(' ');
        currentText.write(word.text);
      } else {
        flush();
        currentSpeaker = speaker;
        turnStart = word.startSec;
        currentText.write(word.text);
      }
    }
    flush();
    return turns;
  }

  static double? _parseOffsetSeconds(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    final match = RegExp(r'^([0-9]*\.?[0-9]+)\s*s?$', caseSensitive: false)
        .firstMatch(raw);
    if (match == null) return null;
    return double.tryParse(match.group(1)!);
  }

  Future<Map<String, dynamic>> _uploadFileRaw({
    required String apiKey,
    required String fileName,
    required String mimeType,
    required List<int> bytes,
  }) async {
    final uri = Uri.parse('$_uploadEndpoint?key=$apiKey');

    final headers = {
      'Content-Type': mimeType,
      'X-Goog-Upload-Protocol': 'raw',
      'X-Goog-Upload-File-Name': fileName,
    };

    final sw = Stopwatch()..start();
    DebugConsole.logApiStart(
      method: 'POST',
      url: uri,
      requestBytes: bytes.length,
      note: 'Gemini file upload',
    );
    DebugConsole.logApiRequest(
      method: 'POST',
      url: uri,
      headers: headers,
      binaryBytes: bytes.length,
    );
    final res = await http.post(
      uri,
      headers: headers,
      body: bytes,
    );
    sw.stop();
    DebugConsole.logApiEnd(
      status: res.statusCode,
      elapsedMs: sw.elapsedMilliseconds,
      responseBytes: res.bodyBytes.length,
    );
    DebugConsole.logApiResponse(
      status: res.statusCode,
      headers: res.headers,
      body: res.body,
      title: 'API response (Gemini upload)',
    );

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final root = json.decode(res.body) as Map<String, dynamic>;
      // Responses from upload API are usually wrapped like {"file": {...}}
      final file = (root['file'] is Map<String, dynamic>)
          ? (root['file'] as Map<String, dynamic>)
          : root;
      if (file['uri'] == null) {
        final name = file['name']?.toString(); // e.g., files/abc123
        if (name != null && name.isNotEmpty) {
          file['uri'] =
              'https://generativelanguage.googleapis.com/v1beta/$name';
        }
      }
      return file;
    }

    String? apiMessage;
    try {
      final err = json.decode(res.body) as Map<String, dynamic>;
      final msg = err['error']?['message'];
      if (msg is String && msg.isNotEmpty) apiMessage = msg;
    } catch (_) {}
    throw AppException.fromHttp(
      res.statusCode,
      apiMessage: apiMessage,
      fallback: 'File upload failed',
    );
  }
}

class _WordAnno {
  const _WordAnno({
    required this.speaker,
    required this.text,
    this.startSec,
  });

  final String speaker;
  final String text;
  final double? startSec;
}
