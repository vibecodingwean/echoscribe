import 'dart:convert';
import 'package:flutter/foundation.dart';

// Lightweight, app-wide debug logger that services can call without
// depending on UI classes. HomePage (or app root) should configure
// the sink and the enabled supplier once.
class DebugConsole {
  static bool Function()? _isEnabled;
  static void Function(String line)? _println;

  static void configure({
    required bool Function() isEnabled,
    required void Function(String line) println,
  }) {
    _isEnabled = isEnabled;
    _println = println;
  }

  static bool get enabled => _isEnabled?.call() == true;

  static void log(String line) {
    if (_isEnabled?.call() == true) {
      _println?.call(line);
    } else {
      // No-op when disabled.
    }
  }

  static void logBlock(String title, String body, {int? truncateAt}) {
    if (!enabled) return;
    final String content;
    if (truncateAt != null && truncateAt > 0 && body.length > truncateAt) {
      content = '${body.substring(0, truncateAt)}… (truncated)';
    } else {
      content = body;
    }
    _println?.call('--- $title ---');
    _println?.call(content);
    _println?.call('--- end of $title ---');
  }

  // Basic API line logs (start/end) for quick glance
  static void logApiStart({required String method, required Uri url, int? requestBytes, String? note}) {
    if (!enabled) return;
    final sizePart = requestBytes != null ? ' | request: ${_fmtBytes(requestBytes)}' : '';
    final notePart = (note != null && note.isNotEmpty) ? ' | $note' : '';
    _println?.call('[API] $method ${_sanitizeUrl(url)}$sizePart$notePart');
  }

  static void logApiEnd({required int status, required int elapsedMs, int? responseBytes}) {
    if (!enabled) return;
    final respPart = responseBytes != null ? ' | response: ${_fmtBytes(responseBytes)}' : '';
    _println?.call('[API] <- $status | ${elapsedMs}ms$respPart');
  }

  // Full request logging (headers + textual body). Use for JSON requests.
  static void logApiRequest({
    required String method,
    required Uri url,
    Map<String, String>? headers,
    String? body,
    int? binaryBytes,
  }) {
    if (!enabled) return;
    _println?.call('--- API request: $method ${_sanitizeUrl(url)} ---');
    if (headers != null && headers.isNotEmpty) {
      _println?.call('Headers:');
      _sanitizeHeaders(headers).forEach((k, v) => _println?.call('  $k: $v'));
    }
    if (body != null) {
      final pretty = _prettyJson(body);
      _println?.call('Body:');
      _println?.call(pretty);
    } else if (binaryBytes != null) {
      _println?.call('Body: <binary ${_fmtBytes(binaryBytes)} omitted>');
    }
    _println?.call('--- end of API request ---');
  }

  // Multipart request logging (fields + file meta only; no raw bytes)
  static void logApiRequestMultipart({
    required String method,
    required Uri url,
    Map<String, String>? headers,
    Map<String, String>? fields,
    List<Map<String, Object?>>? files, // [{field, filename, length, contentType}]
  }) {
    if (!enabled) return;
    _println?.call('--- API request (multipart): $method ${_sanitizeUrl(url)} ---');
    if (headers != null && headers.isNotEmpty) {
      _println?.call('Headers:');
      _sanitizeHeaders(headers).forEach((k, v) => _println?.call('  $k: $v'));
    }
    if (fields != null && fields.isNotEmpty) {
      _println?.call('Fields:');
      fields.forEach((k, v) => _println?.call('  $k: ${_shorten(v, 200)}'));
    }
    if (files != null && files.isNotEmpty) {
      _println?.call('Files:');
      for (final f in files) {
        final field = f['field'];
        final name = f['filename'];
        final len = f['length'];
        final ctype = f['contentType'];
        _println?.call('  $field: name=$name, size=${len ?? 0} B, type=${ctype ?? 'auto'}');
      }
    }
    _println?.call('--- end of API request ---');
  }

  // Full response logging (status, headers, body string)
  static void logApiResponse({
    required int status,
    Map<String, String>? headers,
    String? body,
    String title = 'API response',
  }) {
    if (!enabled) return;
    _println?.call('--- $title ($status) ---');
    if (headers != null && headers.isNotEmpty) {
      _println?.call('Headers:');
      headers.forEach((k, v) => _println?.call('  $k: ${_shorten(v, 400)}'));
    }
    if (body != null) {
      _println?.call(_prettyJson(body));
    }
    _println?.call('--- end of $title ---');
  }

  static String _fmtBytes(int b) {
    if (b < 1024) return '$b B';
    final kb = b / 1024.0;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024.0;
    return '${mb.toStringAsFixed(2)} MB';
  }

  static String _shorten(String v, int max) {
    if (v.length <= max) return v;
    return '${v.substring(0, max)}…';
  }

  static String _prettyJson(String body) {
    try {
      final decoded = json.decode(body);
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(decoded);
    } catch (_) {
      return body;
    }
  }

  static String _sanitizeUrl(Uri url) {
    final q = Map<String, String>.from(url.queryParameters);
    for (final key in q.keys.toList()) {
      final lower = key.toLowerCase();
      if (lower == 'key' || lower.contains('api') || lower.contains('token')) {
        final val = q[key] ?? '';
        q[key] = _redactToken(val);
      }
    }
    return url.replace(queryParameters: q).toString();
  }

  static Map<String, String> _sanitizeHeaders(Map<String, String> headers) {
    final out = <String, String>{};
    headers.forEach((k, v) {
      final lower = k.toLowerCase();
      if (lower == 'authorization' || lower.contains('api-key') || lower.contains('token')) {
        out[k] = _redactToken(v);
      } else {
        out[k] = v;
      }
    });
    return out;
  }

  static String _redactToken(String raw) {
    // Try to preserve token prefix (e.g., Bearer, sk-) and last 4 chars
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return trimmed;
    if (trimmed.toLowerCase().startsWith('bearer ')) {
      final token = trimmed.substring(7);
      return 'Bearer ${_mask(token)}';
    }
    return _mask(trimmed);
  }

  static String _mask(String token) {
    if (token.length <= 8) return '***';
    final last4 = token.substring(token.length - 4);
    return '***$last4';
  }
}
