import 'package:echoscribe/services/recorder_service.dart';
import 'package:echoscribe/services/whisper_service.dart';
import 'package:echoscribe/services/translation_service.dart';
import 'package:echoscribe/services/gemini_service.dart';
import 'package:echoscribe/services/summary_service.dart';
import 'package:echoscribe/services/tts_service.dart';
import 'package:echoscribe/services/secure_storage_service.dart';
import 'package:echoscribe/services/image_service.dart';
import 'package:echoscribe/services/ai/ai_provider_factory.dart';

class ServiceLocator {
  static final ServiceLocator _instance = ServiceLocator._();
  factory ServiceLocator() => _instance;
  ServiceLocator._();

  late final RecorderService recorder;
  late final TtsService tts;
  late final SecureStorageService secureStorage;
  late final AiProviderFactory aiProviderFactory;

  void init() {
    final whisper = WhisperService();
    final gemini = GeminiService();
    final summary = SummaryService();
    final translation = TranslationService();
    final image = ImageService();

    recorder = RecorderService();
    tts = TtsService();
    secureStorage = SecureStorageService();
    aiProviderFactory = AiProviderFactory(
      whisper: whisper,
      gemini: gemini,
      summary: summary,
      translation: translation,
      image: image,
    );
  }
}
