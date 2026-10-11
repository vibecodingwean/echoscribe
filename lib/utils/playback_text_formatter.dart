import 'package:html/parser.dart' show parse;
import 'package:markdown/markdown.dart' as markdown;

/// Produces text for speech without changing the displayed or stored text.
class PlaybackTextFormatter {
  static final _url = RegExp(
    r'''\b(?:https?://|www\.)[^\s<>"']+''',
    caseSensitive: false,
  );
  static final _trailingPunctuation = RegExp(r'[.,;!?]+$');
  static final _spaceBeforePunctuation = RegExp(r'\s+([.,;!?])');
  static final _whitespace = RegExp(r'\s+');
  static final _markdownUrlLink = RegExp(
    r'\[([^\]\n]+)\]\((?:https?://|www\.)[^\s)]+\)',
    caseSensitive: false,
  );
  static final _extractedTextQuote = RegExp(r'^[ \t]*>[ \t]?');
  static final _numberedLine = RegExp(r'^(\s*\d+)\.(?=\s)', multiLine: true);
  static final _htmlTag = RegExp(
    r'''</?(?:h[1-6]|p|div|li|ul|ol|br|blockquote|pre|strong|em|b|i|a)(?:\s+[a-z][\w:-]*\s*=\s*(?:"[^"]*"|'[^']*'))*\s*/?>''',
    caseSensitive: false,
  );
  static const _blockTags = {
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'p',
    'div',
    'li',
    'ul',
    'ol',
    'br',
    'blockquote',
    'pre',
  };

  /// Keep ordinary prose intact. URL extraction has a known display wrapper.
  static String transcript(String text) {
    final lines = text.trim().split('\n');
    if (lines.first.trim() == '#### URL:') {
      final extractedAt =
          lines.indexWhere((line) => line.trim() == '#### EXTRACTED TEXT:');
      if (extractedAt > 0) {
        final extractedText = lines
            .skip(extractedAt + 1)
            .map((line) => line.replaceFirst(_extractedTextQuote, ''))
            .join('\n');
        return _removeUrls(extractedText);
      }
    }
    final withLinkLabels = text.replaceAllMapped(
      _markdownUrlLink,
      (match) => match.group(1)!,
    );
    return _removeUrls(withLinkLabels);
  }

  /// Summaries may contain Markdown and HTML headings, emphasis, and links.
  static String summary(String text) {
    if (text.trim().isEmpty) return '';
    final withoutTags = text.replaceAllMapped(_htmlTag, (match) {
      final tag = RegExp(r'[a-z][\w]*', caseSensitive: false)
          .firstMatch(match.group(0)!)!
          .group(0)!
          .toLowerCase();
      return _blockTags.contains(tag) ? '\n\n' : '';
    });
    // Only '<' can open an HTML tag. Leave '>' intact for Markdown blockquotes
    // and preserve leading dates such as "10. Oktober".
    final markdownText = withoutTags
        .replaceAll('<', '&lt;')
        .replaceAllMapped(_numberedLine, (match) => '${match.group(1)}\\.');
    final html = markdown.markdownToHtml(
      markdownText,
      extensionSet: markdown.ExtensionSet.gitHubFlavored,
    );
    final document = parse(html.replaceAll(_htmlTag, ' '));
    return _removeUrls(document.body?.text ?? '');
  }

  static String _removeUrls(String text) {
    final withoutUrls = text.replaceAllMapped(_url, (match) {
      final value = match.group(0)!;
      return _trailingPunctuation.firstMatch(value)?.group(0) ?? '';
    });
    if (RegExp(r'^[\s.,;!?]*$').hasMatch(withoutUrls)) return '';
    return withoutUrls
        .replaceAllMapped(_spaceBeforePunctuation, (match) => match.group(1)!)
        .replaceAll(_whitespace, ' ')
        .trim();
  }
}
