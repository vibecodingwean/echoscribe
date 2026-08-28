import 'package:echoscribe/config/prompts.dart';
import 'package:echoscribe/services/speakers/native_speaker_formatter.dart';
import 'package:echoscribe/services/speakers/speaker_aware_summary.dart';
import 'package:echoscribe/services/speakers/speaker_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NativeSpeakerFormatter', () {
    test('formats and merges consecutive same-speaker turns', () {
      final text = NativeSpeakerFormatter.format(const [
        SpeakerTurn(speaker: 'spk_1', text: 'Hello'),
        SpeakerTurn(speaker: 'spk_1', text: 'there'),
        SpeakerTurn(speaker: 'spk_2', text: 'Hi'),
        SpeakerTurn(speaker: 'Speaker 2', text: 'again'),
        SpeakerTurn(speaker: 'spk_1', text: 'Bye'),
      ]);

      expect(
        text,
        'Speaker 1: Hello there\nSpeaker 2: Hi again\nSpeaker 1: Bye',
      );
    });

    test('normalizes spk labels to Speaker N', () {
      expect(NativeSpeakerFormatter.normalizeSpeakerLabel('spk_3'), 'Speaker 3');
      expect(
        NativeSpeakerFormatter.normalizeSpeakerLabel('Speaker 4'),
        'Speaker 4',
      );
    });
  });

  group('SpeakerAwareSummary', () {
    test('keeps default synthetic prompt when no native labels', () {
      final prompt = SpeakerAwareSummary.resolvePrompt(
        text: 'Just a monologue without labels.',
        summaryPrompt: kDefaultSummaryPrompt,
      );
      expect(prompt, kDefaultSummaryPrompt);
    });

    test('uses native preserve prompt for default + Speaker N labels', () {
      final prompt = SpeakerAwareSummary.resolvePrompt(
        text: 'Speaker 1: Hello\nSpeaker 2: Hi',
        summaryPrompt: kDefaultSummaryPrompt,
      );
      expect(prompt, kNativeSpeakerSummaryPrompt);
      expect(prompt.contains('PRESERVE'), isTrue);
      expect(prompt.toLowerCase().contains('do not invent extra speakers'), isTrue);
    });

    test('uses native prompt when source is nativeApi even without labels', () {
      final prompt = SpeakerAwareSummary.resolvePrompt(
        text: 'Hello there',
        summaryPrompt: null,
        source: SpeakerSource.nativeApi,
      );
      expect(prompt, kNativeSpeakerSummaryPrompt);
    });

    test('appends instruction for customized prompt with labels', () {
      const custom = 'Be witty and short.';
      final prompt = SpeakerAwareSummary.resolvePrompt(
        text: 'Speaker 1: Hello',
        summaryPrompt: custom,
      );
      expect(prompt.startsWith(custom), isTrue);
      expect(prompt.contains(kNativeSpeakerInstruction), isTrue);
    });
  });

  group('modelSupportsNativeSpeakers', () {
    test('true only for dedicated file STT model', () {
      expect(modelSupportsNativeSpeakers('gemini-3.5-transcribe'), isTrue);
      expect(
        modelSupportsNativeSpeakers('gemini-3.5-transcribe-live'),
        isFalse,
      );
      expect(modelSupportsNativeSpeakers('gemini-3.7-flash'), isFalse);
    });
  });
}
