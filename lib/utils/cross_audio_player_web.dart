import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

class CrossAudioPlayer {
  web.HTMLAudioElement? _audio;
  final _controller = StreamController<bool>.broadcast();
  final _endedController = StreamController<void>.broadcast();
  late final JSFunction _onEndedJs = (() {
    _controller.add(false);
    _endedController.add(null);
  }).toJS;
  late final JSFunction _onPlayJs = (() {
    _controller.add(true);
  }).toJS;
  late final JSFunction _onPauseJs = (() {
    _controller.add(false);
  }).toJS;

  // Emits true when playing, false on pause/stop/end
  Stream<bool> get onPlayingChanged => _controller.stream;
  // Emits a ping when playback naturally completed (ended event)
  Stream<void> get onEnded => _endedController.stream;

  Future<void> playBytes(Uint8List bytes, {String? mimeType}) async {
    debugPrint(
        'CrossAudioPlayer.web: playBytes len=${bytes.length} mime=$mimeType');
    await stop();

    final dataUrl =
        Uri.dataFromBytes(bytes, mimeType: mimeType ?? 'audio/mpeg').toString();

    final a = web.HTMLAudioElement()
      ..src = dataUrl
      ..autoplay = true
      ..controls = false;

    a.addEventListener('ended', _onEndedJs);
    a.addEventListener('play', _onPlayJs);
    a.addEventListener('pause', _onPauseJs);

    _audio = a;
    try {
      a.play();
      _controller.add(true);
    } catch (_) {
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
        a.play();
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
        _audio!
          ..removeEventListener('ended', _onEndedJs)
          ..removeEventListener('play', _onPlayJs)
          ..removeEventListener('pause', _onPauseJs)
          ..src = ''
          ..load();
      }
    } finally {
      _audio = null;
      _controller.add(false);
    }
  }
}
