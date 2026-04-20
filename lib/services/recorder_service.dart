import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

class RecorderService {
  final AudioRecorder _record = AudioRecorder();

  Future<bool> hasPermission() async => await _record.hasPermission();
  Future<bool> isRecording() async => await _record.isRecording();

  // Stream a normalized input level (0..1) derived from mic amplitude.
  // More sensitive mapping with a gentle gamma curve to amplify quiet signals.
  Stream<double> levelStream(
      {Duration interval = const Duration(milliseconds: 120)}) {
    return _record.onAmplitudeChanged(interval).map((amp) {
      // Amplitude.current is in dB, typically [-160, 0]. Map roughly [-90, 0] to [0, 1]
      // and apply a gamma (<1) to boost lower levels for a more responsive flicker.
      final double db = amp.current;
      final double norm = ((db + 90.0) / 90.0).clamp(0.0, 1.0);
      final double level = math.pow(norm, 0.35).toDouble();
      return level;
    });
  }

  // Start recording using a platform-appropriate configuration.
  // On web, use webm/Opus which is supported by browsers. On mobile/desktop, AAC/M4A.
  Future<String?> startRecording() async {
    if (!await hasPermission()) return null;
    final now = DateTime.now().millisecondsSinceEpoch;

    final RecordConfig cfg = kIsWeb
        ? const RecordConfig(
            encoder: AudioEncoder.opus,
            bitRate: 128000,
            sampleRate: 48000,
            numChannels: 1,
          )
        : const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 128000,
            sampleRate: 44100,
            numChannels: 1,
          );

    final String path;
    if (kIsWeb) {
      path = 'web_record_$now.webm';
    } else {
      final dir = await getApplicationDocumentsDirectory();
      path = '${dir.path}/echoscribe_$now.m4a';
    }

    await _record.start(cfg, path: path);

    // We'll rely on stop() to return the actual persisted path (mobile/desktop)
    // or a blob: URL (web).
    return null;
  }

  Future<String?> stopRecording() async {
    if (!await _record.isRecording()) return null;
    return await _record.stop();
  }

  Future<void> dispose() async {
    if (await _record.isRecording()) {
      await _record.stop();
    }
  }
}
