import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;
import 'package:brotli/brotli.dart';
import 'package:echoscribe/services/debug_console.dart';

class UrlContentService {
  // Simple in-memory cache to avoid redundant fetches in the same session
  static final Map<String, String> _cache = {};

  static bool hasCached(String url) => _cache.containsKey(url);

  /// Fetches the HTML content of a URL and extracts the visible text.
  /// Removes <script>, <style>, and other non-content tags.
  static Future<String> fetchText(String url, {Duration timeout = const Duration(seconds: 10)}) async {
    if (_cache.containsKey(url)) {
      return _cache[url]!;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) throw Exception('Invalid URL');

    final sw = Stopwatch()..start();
    DebugConsole.logApiStart(method: 'GET', url: uri, note: 'Fetching URL content for extraction');

    try {
      final response = await http.get(uri, headers: {
        'Accept-Encoding': 'gzip, deflate, br',
        'User-Agent': 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      }).timeout(timeout);
      sw.stop();
      DebugConsole.logApiEnd(status: response.statusCode, elapsedMs: sw.elapsedMilliseconds, responseBytes: response.bodyBytes.length);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Failed to fetch URL: ${response.statusCode}');
      }

      // Check for compression
      final encoding = response.headers['content-encoding']?.toLowerCase();
      List<int> bytes = response.bodyBytes;

      if (encoding == 'br') {
        // Handle Brotli decompression
        try {
          bytes = brotli.decode(bytes);
        } catch (e) {
          throw Exception('Brotli decompression failed: $e');
        }
      } else if (encoding == 'gzip') {
         // Manual gzip if needed (though http package usually handles it)
         try {
           bytes = gzip.decode(bytes);
         } catch (_) {}
      }

      // Robust decoding
      String html;
      try {
        html = utf8.decode(bytes, allowMalformed: true);
      } catch (e) {
        html = latin1.decode(bytes);
      }

      final document = parse(html);      
      // Remove noise
      document.querySelectorAll('script, style, head, nav, footer, iframe, noscript').forEach((e) => e.remove());

      // Extract text
      final text = document.body?.text ?? '';
      
      // Clean up whitespace: replace multiple spaces/newlines with a single one
      final cleanedText = text.replaceAll(RegExp(r'\s+'), ' ').trim();

      if (cleanedText.isEmpty) {
        throw Exception('No text content found at URL');
      }

      _cache[url] = cleanedText;
      return cleanedText;
    } catch (e) {
      if (sw.isRunning) sw.stop();
      DebugConsole.logApiEnd(status: 0, elapsedMs: sw.elapsedMilliseconds);
      rethrow;
    }
  }
}
