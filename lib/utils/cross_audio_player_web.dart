import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';

class CrossAudioPlayer {
  html.AudioElement? _audio;
  String? _objectUrl;
  final _controller = StreamController<bool>.broadcast();
  final _endedController = StreamController<void>.broadcast();

  // Emits true when playing, false on pause/stop/end
  Stream<bool> get onPlayingChanged => _controller.stream;
  // Emits a ping when playback naturally completed (ended event)
  Stream<void> get onEnded => _endedController.stream;

  Future<void> playBytes(Uint8List bytes, {String? mimeType}) async {
    debugPrint('CrossAudioPlayer.web: playBytes len=${bytes.length} mime=$mimeType');
    // Stop any existing playback and release previous URL
    await stop();

    final blob = html.Blob([bytes], mimeType ?? 'audio/mpeg');
    final url = html.Url.createObjectUrlFromBlob(blob);
    _objectUrl = url;

    final a = html.AudioElement(url)
      ..autoplay = true
      ..controls = false;

    // Wire events
    a.onEnded.listen((_) {
      _controller.add(false);
      _endedController.add(null);
    });
    a.onPlay.listen((_) {
      _controller.add(true);
    });
    a.onPause.listen((_) {
      _controller.add(false);
    });

    _audio = a;
    // Attempt to play; browsers may require a user gesture (button press), which we have
    try {
      await a.play();
      _controller.add(true);
    } catch (_) {
      // If autoplay fails for any reason, surface as not playing
      _controller.add(false);
      rethrow;
    }
  }

  Future<void> pause() async {
    debugPrint('CrossAudioPlayer.web: pause');
    _audio?.pause();
    _controller.add(false);
  }

  Future<void> resume() async {
    debugPrint('CrossAudioPlayer.web: resume');
    final a = _audio;
    if (a != null) {
      try {
        await a.play();
        _controller.add(true);
      } catch (_) {
        _controller.add(false);
        rethrow;
      }
    }
  }

  Future<void> stop() async {
    debugPrint('CrossAudioPlayer.web: stop');
    try {
      _audio?.pause();
      if (_audio != null) {
        _audio!..src = ''..load();
      }
    } finally {
      if (_objectUrl != null) {
        html.Url.revokeObjectUrl(_objectUrl!);
        _objectUrl = null;
      }
      _audio = null;
      _controller.add(false);
    }
  }
}
