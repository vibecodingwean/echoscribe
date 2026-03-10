import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;
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
      final response = await http.get(uri).timeout(timeout);
      sw.stop();
      DebugConsole.logApiEnd(status: response.statusCode, elapsedMs: sw.elapsedMilliseconds, responseBytes: response.bodyBytes.length);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Failed to fetch URL: ${response.statusCode}');
      }

      final document = parse(response.body);
      
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
