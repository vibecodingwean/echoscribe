import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class CrossAudioPlayer {
  final AudioPlayer _player = AudioPlayer();
  final _controller = StreamController<bool>.broadcast();
  final _endedController = StreamController<void>.broadcast();

  Stream<bool> get onPlayingChanged => _controller.stream;
  Stream<void> get onEnded => _endedController.stream;

  CrossAudioPlayer() {
    _player.onPlayerStateChanged.listen((state) {
      final isPlaying = state == PlayerState.playing;
      _controller.add(isPlaying);
    });
    _player.onPlayerComplete.listen((_) {
      _controller.add(false);
      _endedController.add(null);
    });
  }

  Future<void> playBytes(Uint8List bytes, {String? mimeType}) async {
    try {
      await stop();

      final tempDir = await getTemporaryDirectory();
      final ext = (mimeType?.contains('wav') ?? false)
          ? 'wav'
          : (mimeType?.contains('aac') ?? false)
              ? 'aac'
              : (mimeType?.contains('m4a') ?? false)
                  ? 'm4a'
                  : 'mp3';
      final file = File('${tempDir.path}/temp_audio_playback.$ext');
      await file.writeAsBytes(bytes, flush: true);

      debugPrint('CrossAudioPlayer.io: wrote ${bytes.length} bytes to ${file.path}');
      await _player.play(DeviceFileSource(file.path));
    } catch (e, st) {
      debugPrint('CrossAudioPlayer.io error: $e\n$st');
      _controller.add(false);
      rethrow;
    }
  }

  Future<void> pause() async {
    try {
      await _player.pause();
    } catch (e) {
      debugPrint('CrossAudioPlayer.io pause error: $e');
    }
  }

  Future<void> resume() async {
    try {
      await _player.resume();
    } catch (e) {
      debugPrint('CrossAudioPlayer.io resume error: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('CrossAudioPlayer.io stop error: $e');
    } finally {
      _controller.add(false);
    }
  }
}
