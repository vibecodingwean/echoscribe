import 'package:flutter/material.dart';

import 'package:echoscribe/state/settings_state.dart';
import 'package:echoscribe/state/content_state.dart';
import 'package:echoscribe/services/ai/ai_provider_factory.dart';
import 'package:echoscribe/services/url_handler.dart';

/// Utilities for handling Share-Intent text specifically (not clipboard).
///
/// - Extracts the first valid http/https URL from mixed content like
///   "Some title – Source https://example.com/article?id=1".
/// - Applies only to share-intents; clipboard behavior remains unchanged.
class ShareIntentHandler {
  const ShareIntentHandler._();

  /// Attempts to extract the first http/https URL from a free-form string.
  /// Returns the cleaned URL or null if none is found.
  ///
  /// Robustness notes:
  /// - Matches http/https schemes only.
  /// - Trims surrounding angle brackets and trailing punctuation often added by apps.
  /// - Avoids grabbing trailing characters like closing parentheses, commas, or quotes.
  static String? extractFirstHttpUrl(String text) {
    if (text.isEmpty) return null;
    // Quick path for single-token URLs that already validate
    if (UrlHandler.looksLikeSingleUrl(text)) return text.trim();

    // Regex to find http/https URLs in mixed text.
    // Captures until whitespace or a typical trailing punctuation.
    final urlRegex = RegExp(r'(https?:\/\/[^\s<>"]+)', multiLine: true);
    final match = urlRegex.firstMatch(text);
    if (match == null) return null;

    String url = match.group(0)!.trim();

    // Remove common trailing punctuation/symbols that are not part of the URL
    // e.g., ")", ".", ",", ";", ":", "!", "?", "\u201d" (right quote)
    url = url.replaceAll(RegExp(r'[\)\]\}\.,;:!?\u201d\u2019]+$'), '');

    // Remove wrapping brackets often used in shared content
    if (url.startsWith('<') && url.endsWith('>')) {
      url = url.substring(1, url.length - 1);
    }

    // Final sanity check
    return UrlHandler.looksLikeSingleUrl(url) ? url : null;
  }

  /// For share-intent text: try to extract a URL and process it via UrlHandler.
  /// Returns true if handled as URL; false if no valid URL could be extracted.
  static Future<bool> tryHandleSharedText({
    required BuildContext context,
    required String textContent,
    required SettingsState settings,
    required ContentState content,
    required AiProviderFactory aiFactory,
    void Function(String message)? showError,
    void Function(String message)? showSuccess,
  }) async {
    final url = extractFirstHttpUrl(textContent.trim());
    if (url == null) return false;

    await UrlHandler.processUrl(
      context: context,
      settings: settings,
      content: content,
      aiFactory: aiFactory,
      url: url,
      showError: showError,
      showSuccess: showSuccess,
    );
    return true;
  }
}
