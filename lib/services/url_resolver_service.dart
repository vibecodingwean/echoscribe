import 'dart:async';
import 'package:http/http.dart' as http;

/// Result of attempting to resolve a potentially shortened URL.
class UrlResolverResult {
  final String url;
  final bool wasShortDomain;
  final bool resolved; // True if the final URL differs from the input due to redirects
  final int hops;
  final String? error;

  const UrlResolverResult({
    required this.url,
    required this.wasShortDomain,
    required this.resolved,
    required this.hops,
    this.error,
  });
}

/// Service that resolves known short/redirect URLs (e.g., t.co, bit.ly) to their final targets.
/// The logic is encapsulated here to keep UI layers clean.
class UrlResolverService {
  UrlResolverService._();

  // Whitelist of known redirect/shortener domains. Subdomains are allowed.
  static const Set<String> _redirectDomains = {
    'search.app',
    'lnkd.in',
    't.co',
    'bit.ly',
    'fb.watch',
    'share.google',
  };

  /// Checks whether a host belongs to the whitelist (supports subdomains).
  static bool _isWhitelistedHost(String host) {
    if (host.isEmpty) return false;
    final h = host.toLowerCase();
    for (final d in _redirectDomains) {
      if (h == d) return true;
      if (h.endsWith('.$d')) return true;
    }
    return false;
  }

  /// Attempt to resolve a short/redirect URL to the final target.
  /// - Only attempts resolution when the host is whitelisted.
  /// - Follows up to [maxRedirects] levels by manually reading the Location header.
  /// - Uses HEAD first, falls back to GET if necessary.
  /// - On any error/timeout, returns the original URL with an error message.
  static Future<UrlResolverResult> resolveIfShort(
    String inputUrl, {
    int maxRedirects = 3,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final parsed = Uri.tryParse(inputUrl);
    if (parsed == null || (parsed.scheme != 'http' && parsed.scheme != 'https') || parsed.host.isEmpty) {
      return UrlResolverResult(url: inputUrl, wasShortDomain: false, resolved: false, hops: 0);
    }

    if (!_isWhitelistedHost(parsed.host)) {
      return UrlResolverResult(url: inputUrl, wasShortDomain: false, resolved: false, hops: 0);
    }

    Uri current = parsed;
    int hops = 0;
    try {
      final client = http.Client();
      try {
        while (hops < maxRedirects) {
          // Try HEAD first to avoid downloading body
          final headReq = http.Request('HEAD', current);
          headReq.followRedirects = false; // we want to inspect 3xx ourselves
          final headStreamed = await client.send(headReq).timeout(timeout);
          final headRes = await http.Response.fromStream(headStreamed);

          if (headRes.isRedirect && headRes.headers.containsKey('location')) {
            final loc = headRes.headers['location']!;
            Uri? next;
            try {
              final locUri = Uri.parse(loc);
              next = locUri.isAbsolute ? locUri : current.resolve(loc);
            } catch (_) {
              next = null;
            }
            if (next == null) break;
            current = next;
            hops += 1;
            continue;
          }

          // Some services might not support HEAD; try a minimal GET without following redirects
          final getReq = http.Request('GET', current);
          getReq.followRedirects = false;
          // Hint to servers we don't need the full body
          getReq.headers['Range'] = 'bytes=0-0';
          final getStreamed = await client.send(getReq).timeout(timeout);
          final getRes = await http.Response.fromStream(getStreamed);
          if (getRes.isRedirect && getRes.headers.containsKey('location')) {
            final loc = getRes.headers['location']!;
            Uri? next;
            try {
              final locUri = Uri.parse(loc);
              next = locUri.isAbsolute ? locUri : current.resolve(loc);
            } catch (_) {
              next = null;
            }
            if (next == null) break;
            current = next;
            hops += 1;
            continue;
          }

          // Not a redirect -> final
          break;
        }
      } finally {
        client.close();
      }

      final finalUrl = current.toString();
      final resolved = finalUrl != inputUrl;
      return UrlResolverResult(
        url: finalUrl,
        wasShortDomain: true,
        resolved: resolved,
        hops: hops,
      );
    } catch (e) {
      return UrlResolverResult(
        url: inputUrl,
        wasShortDomain: true,
        resolved: false,
        hops: hops,
        error: e.toString(),
      );
    }
  }
}
