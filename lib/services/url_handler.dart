import "package:echoscribe/services/ai/ai_provider_factory.dart";
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_handler/share_handler.dart';
import 'package:echoscribe/state/settings_state.dart';
import 'package:echoscribe/state/content_state.dart';
import 'package:echoscribe/models/enums.dart';
import 'package:echoscribe/config/prompts.dart';
import 'package:echoscribe/services/url_resolver_service.dart';
import 'package:echoscribe/services/url_content_service.dart';
import 'package:echoscribe/models/transcription_item.dart';
import 'package:echoscribe/pages/settings_page.dart';
import 'package:echoscribe/models/app_exception.dart';

class UrlHandler {
  const UrlHandler._();

  // Simple URL validator for single-token http/https links
  static bool looksLikeSingleUrl(String input) {
    final t = input.trim();
    if (t.isEmpty) return false;
    if (t.contains(' ') || t.contains('\n') || t.contains('\t')) return false;
    final uri = Uri.tryParse(t);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  /// Try to extract a single URL from a SharedMedia event and process it.
  /// Returns true if a URL was detected and handled; false otherwise.
  static Future<bool> tryHandleSharedMediaUrl({
    required BuildContext context,
    required SharedMedia media,
    required SettingsState settings,
    required ContentState content,
    required AiProviderFactory aiFactory,
    void Function(String message)? showError,
    void Function(String message)? showSuccess,
  }) async {
    final mediaContent = (media.content ?? '').trim();
    if (mediaContent.isEmpty) return false;
    if (!looksLikeSingleUrl(mediaContent)) return false;

    await processUrl(
      context: context,
      settings: settings,
      content: content,
      aiFactory: aiFactory,
      url: mediaContent,
      showError: showError,
      showSuccess: showSuccess,
    );
    return true;
  }

  /// Reads Clipboard.kTextPlain; if it's a single URL, process it and return true.
  /// If clipboard doesn't contain a URL, returns false so caller can fallback to text processing.
  static Future<bool> tryPasteAndProcessUrl({
    required BuildContext context,
    required SettingsState settings,
    required ContentState content,
    required AiProviderFactory aiFactory,
    void Function(String message)? showError,
    void Function(String message)? showSuccess,
  }) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      if (showError != null) showError('Nothing to paste');
      return true; // handled (by notifying user)
    }
    if (!looksLikeSingleUrl(text)) return false;

    if (showSuccess != null) showSuccess('URL pasted and summary initiated');
    if (!context.mounted) return true;

    await processUrl(
      context: context,
      settings: settings,
      content: content,
      aiFactory: aiFactory,
      url: text,
      showError: showError,
      showSuccess: showSuccess,
    );
    return true;
  }

  /// Centralized flow to process a URL: show in transcript, call LLM summarizer, update state & history, copy to clipboard.
  static Future<void> processUrl({
    required BuildContext context,
    required SettingsState settings,
    required ContentState content,
    required AiProviderFactory aiFactory,
    required String url,
    void Function(String message)? showError,
    void Function(String message)? showSuccess,
  }) async {
    // Provide local helpers for snackbars when callbacks are not provided
    void showError0(String m) {
      if (showError != null) return showError(m);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m),
        duration: const Duration(milliseconds: 1000),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    }

    void showInfo(String m) {
      if (showSuccess != null) return showSuccess(m);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m),
        duration: const Duration(milliseconds: 1200),
      ));
    }

    if (!settings.hasActiveApiKey) {
      showError0('Add your API key first');
      await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => SettingsPage(settings: settings)));
      if (!context.mounted) return;
      return;
    }

    if (!looksLikeSingleUrl(url)) {
      showError0('Invalid URL');
      return;
    }

    content.clearTranscription();
    content.setTranscribing(true);
    content.appendLogLine('Processing shared URL');

    try {
      // 1) Resolve short/redirect URLs (whitelisted domains only)
      content.appendLogLine('Checking for short-link redirection');
      final resolution = await UrlResolverService.resolveIfShort(url);
      final effectiveUrl = resolution.url;
      if (resolution.wasShortDomain) {
        if (resolution.resolved) {
          content.appendLogLine(
              'Short link resolved in ${resolution.hops} hop(s)');
        } else if (resolution.error != null) {
          content
              .appendLogLine('Redirect resolution failed: ${resolution.error}');
          showInfo(
              'Die Weiterleitung konnte nicht aufgelöst werden, die Zusammenfassung kann unvollständig sein.');
        } else {
          content.appendLogLine('No redirect detected on whitelisted domain');
        }
      }

      // 2) Show the (final) URL in transcript panel
      content.setCurrentTranscript(effectiveUrl);

      String contentToSummarize = effectiveUrl;

      // Force extraction if the provider requires it (Claude/Grok) or user enabled it
      final shouldExtract =
          settings.appFetchUrl || settings.provider.mustExtractUrl;

      if (shouldExtract) {
        content.appendLogLine('--------------------');

        if (settings.provider.mustExtractUrl) {
          content.appendLogLine(
              '💡 ${settings.provider.brandName} requires local content extraction');
        }

        // Use the cache check directly to provide a specific log entry
        if (UrlContentService.hasCached(effectiveUrl)) {
          content.appendLogLine('📦 Content found in local cache');
        } else {
          content.appendLogLine('🌐 Requesting page content...');
        }

        try {
          final text = await UrlContentService.fetchText(effectiveUrl);
          if (!UrlContentService.hasCached(effectiveUrl)) {
            content.appendLogLine('✅ Content retrieved (${text.length} chars)');
          }
          content.appendLogLine('📄 Extracting visible text...');

          contentToSummarize = text;

          // Update transcription panel: Show URL + Extracted Text
          final displayBuffer = StringBuffer();
          displayBuffer.writeln('#### URL:');
          displayBuffer
              .writeln('[$effectiveUrl]($effectiveUrl)'); // Markdown link
          displayBuffer.writeln('');
          displayBuffer.writeln(
              '........................................'); // Subtle "thread"
          displayBuffer.writeln('');
          displayBuffer.writeln('#### EXTRACTED TEXT:');
          displayBuffer.writeln('');
          // Prefixes each line with '>' to create a blockquote
          final lines = text.split('\n');
          for (final line in lines) {
            displayBuffer.writeln('> $line');
          }
          content.setCurrentTranscript(displayBuffer.toString());
          content.appendLogLine('📦 Preparing data for AI...');
        } catch (e) {
          content.appendLogLine('⚠️ Extraction failed: $e');
          content.appendLogLine('🔄 Falling back: AI will try URL');
          // contentToSummarize remains the URL
        }
        content.appendLogLine('--------------------');
      } else {
        content.appendLogLine('📡 Sending URL to AI provider...');
      }

      // Store the SOURCE content (either extracted text or the URL)
      // so that re-translation logic in HomePage can re-process it.
      content.setSourceTranscript(contentToSummarize);

      // 3) Summarize via selected provider
      final ai = aiFactory.create(settings.provider);

      String getModelForSummary() {
        switch (settings.provider) {
          case AiProviderType.gemini:
            return AiModelConfig.geminiSummary(pro: settings.geminiPro);
          case AiProviderType.anthropic:
            return AiModelConfig.anthropicSummary(pro: settings.anthropicPro);
          case AiProviderType.xai:
            return AiModelConfig.xaiSummary(pro: settings.xaiPro);
          case AiProviderType.openai:
            return AiModelConfig.openAiSummary(pro: settings.openAiPro);
        }
      }

      final model = getModelForSummary();
      final providerName = '🤖 ${settings.provider.brandName}';
      content.appendLogLine('$providerName\n($model) is analyzing...');

      final summary = await ai.summarize(
        apiKey: settings.activeApiKey,
        text: contentToSummarize,
        model: model,
        targetLanguageCode: settings.targetLanguageCode,
        summaryPrompt: settings.urlSummaryPrompt,
      );
      content.appendLogLine('✨ Summary received successfully');
      content.appendLogLine('Received summary');
      content.setCurrentSummary(summary);
      content.setOutputMode(OutputMode.summary);
      if (settings.debugMode) {
        content.appendLogLine('Response (summary):');
        content.appendLogLine(summary);
      }

      // History: transcription holds the (final) URL, summary holds the summary
      final created = TranscriptionItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: summary, // show summary preview in the list
        createdAt: DateTime.now(),
        duration: null,
        language: settings.targetLanguageCode,
        transcript: effectiveUrl,
        summary: summary,
        mode: 'summary',
      );
      content.addHistory(created);
      content.setActiveHistory(created.id);

      try {
        await content.addToClipboard(summary);
        showInfo('Summary copied to clipboard');
      } catch (e) {
        // Clipboard writes can fail on web without a direct user gesture.
        if (settings.debugMode) {
          content.appendLogLine('Clipboard copy failed: ${e.toString()}');
        }
        showInfo('Summary ready (copy to clipboard failed).');
      }
    } on AppException catch (e) {
      content.appendLogLine('⚠️ ${e.userMessage}');
      showError0(e.userMessage);
    } catch (e) {
      content.appendLogLine('⚠️ $e');
      showError0('URL could not be processed');
    } finally {
      content.setTranscribing(false);
    }
  }
}
