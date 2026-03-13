import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:echoscribe/services/debug_console.dart';
import 'package:echoscribe/models/app_exception.dart';

class ImageService {
  Future<Uint8List> generateImageOpenAI({
    required String apiKey,
    required String prompt,
    required String model,
  }) async {
    final uri = Uri.parse('https://api.openai.com/v1/images/generations');
    final headers = {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    };
    final body = json.encode({
      'model': model,
      'prompt': prompt,
      // 'response_format': 'b64_json', // Removed because of error
    });

    final sw = Stopwatch()..start();
    DebugConsole.logApiStart(method: 'POST', url: uri, requestBytes: utf8.encode(body).length, note: 'OpenAI Image Gen');
    final res = await http.post(uri, headers: headers, body: body);
    sw.stop();
    DebugConsole.logApiEnd(status: res.statusCode, elapsedMs: sw.elapsedMilliseconds, responseBytes: res.bodyBytes.length);
    
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = json.decode(res.body) as Map<String, dynamic>;
      final item = data['data']?[0];
      
      // Try base64 first (Often default or preferred)
      final b64 = item?['b64_json'] as String?;
      if (b64 != null && b64.isNotEmpty) {
        return base64Decode(b64);
      }
      
      // Fallback to URL download
      final url = item?['url'] as String?;
      if (url != null && url.isNotEmpty) {
        final imgRes = await http.get(Uri.parse(url));
        if (imgRes.statusCode == 200) {
          return imgRes.bodyBytes;
        }
      }
      throw const EmptyResultException('Empty image result');
    }

    String? apiMessage;
    try {
      final err = json.decode(res.body) as Map<String, dynamic>;
      final msg = err['error']?['message'];
      if (msg is String && msg.isNotEmpty) apiMessage = msg;
    } catch (_) {}
    throw AppException.fromHttp(res.statusCode, apiMessage: apiMessage, fallback: 'OpenAI image generation failed');
  }

  Future<Uint8List> generateImageXai({
    required String apiKey,
    required String prompt,
    required String model,
  }) async {
    final uri = Uri.parse('https://api.x.ai/v1/images/generations');
    final headers = {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    };
    final body = json.encode({
      'model': model,
      'prompt': prompt,
      // 'response_format': 'b64_json', // Removed because of error
    });

    final sw = Stopwatch()..start();
    DebugConsole.logApiStart(method: 'POST', url: uri, requestBytes: utf8.encode(body).length, note: 'xAI Image Gen');
    final res = await http.post(uri, headers: headers, body: body);
    sw.stop();
    DebugConsole.logApiEnd(status: res.statusCode, elapsedMs: sw.elapsedMilliseconds, responseBytes: res.bodyBytes.length);
    
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = json.decode(res.body) as Map<String, dynamic>;
      final item = data['data']?[0];
      
      // Try base64 first (Often default or preferred)
      final b64 = item?['b64_json'] as String?;
      if (b64 != null && b64.isNotEmpty) {
        return base64Decode(b64);
      }
      
      // Fallback to URL download
      final url = item?['url'] as String?;
      if (url != null && url.isNotEmpty) {
        final imgRes = await http.get(Uri.parse(url));
        if (imgRes.statusCode == 200) {
          return imgRes.bodyBytes;
        }
      }
      throw const EmptyResultException('Empty image result');
    }

    String? apiMessage;
    try {
      final err = json.decode(res.body) as Map<String, dynamic>;
      final msg = err['error']?['message'];
      if (msg is String && msg.isNotEmpty) apiMessage = msg;
    } catch (_) {}
    throw AppException.fromHttp(res.statusCode, apiMessage: apiMessage, fallback: 'xAI image generation failed');
  }

  Future<Uint8List> generateImageGemini({
    required String apiKey,
    required String prompt,
    required String model,
  }) async {
    final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey');
    final headers = {'Content-Type': 'application/json'};
    final body = json.encode({
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ]
    });

    final sw = Stopwatch()..start();
    DebugConsole.logApiStart(method: 'POST', url: uri, requestBytes: utf8.encode(body).length, note: 'Gemini Image Gen');
    final res = await http.post(uri, headers: headers, body: body);
    sw.stop();
    DebugConsole.logApiEnd(status: res.statusCode, elapsedMs: sw.elapsedMilliseconds, responseBytes: res.bodyBytes.length);
    
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = json.decode(res.body) as Map<String, dynamic>;
      final candidates = data['candidates'] as List<dynamic>?;
      if (candidates != null && candidates.isNotEmpty) {
        final parts = candidates[0]['content']?['parts'] as List<dynamic>?;
        if (parts != null && parts.isNotEmpty) {
          final inlineData = parts[0]['inlineData'];
          if (inlineData != null) {
            final b64 = inlineData['data'] as String?;
            if (b64 != null && b64.isNotEmpty) {
              return base64Decode(b64);
            }
          }
        }
      }
      throw const EmptyResultException('Empty image result');
    }

    String? apiMessage;
    try {
      final err = json.decode(res.body) as Map<String, dynamic>;
      final msg = err['error']?['message'];
      if (msg is String && msg.isNotEmpty) apiMessage = msg;
    } catch (_) {}
    throw AppException.fromHttp(res.statusCode, apiMessage: apiMessage, fallback: 'Gemini image generation failed');
  }
}
