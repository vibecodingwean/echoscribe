import 'package:html/parser.dart' show parse;
import 'package:markdown/markdown.dart' as markdown;

/// Converts displayed Markdown/HTML into words suitable for speech providers.
class PlaybackTextFormatter {
  static final _url = RegExp(
    r'\b(?:https?://|www\.)[^\s<>"\]]+',
    caseSensitive: false,
  );
  static final _blockTags = RegExp(
    r'</?(?:h[1-6]|p|div|li|ul|ol|br|blockquote|pre)[^>]*>',
    caseSensitive: false,
  );

  static String format(String text) {
    if (text.trim().isEmpty) return '';
    final html = markdown.markdownToHtml(
      text.replaceAll(_blockTags, '\n\n'),
      extensionSet: markdown.ExtensionSet.gitHubFlavored,
    );
    final document = parse(html.replaceAll(_blockTags, ' '));
    document.querySelectorAll('script, style').forEach((element) {
      element.remove();
    });
    final plainText = document.body?.text ?? '';
    return plainText
        .replaceAll(_url, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
