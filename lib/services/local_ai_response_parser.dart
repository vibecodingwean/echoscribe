import 'dart:convert';

import 'package:echoscribe/models/app_exception.dart';

class LocalAiResponseParser {
  const LocalAiResponseParser._();

  static String ollamaMessageContent(String body) {
    final data = json.decode(body) as Map<String, dynamic>;
    final message = data['message'];
    final content = message is Map ? message['content']?.toString() ?? '' : '';
    if (content.trim().isEmpty) {
      throw const EmptyResultException('Local AI returned empty text');
    }
    return content.trim();
  }

  static String whisperText(String body) {
    final data = json.decode(body) as Map<String, dynamic>;
    final text = data['text']?.toString() ?? '';
    if (text.trim().isEmpty) {
      throw const EmptyResultException('Transcription returned empty text');
    }
    return text.trim();
  }
}
