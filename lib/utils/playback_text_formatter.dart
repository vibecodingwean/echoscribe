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

  /// A transcript can be ordinary prose, including dates and comparisons.
  static String transcript(String text) => _removeUrls(text);

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
    // Preserve literal comparisons: the HTML parser must not treat <b und >
    // as a tag. Also retain leading dates such as "10. Oktober" in Markdown.
    final markdownText = withoutTags
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
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
