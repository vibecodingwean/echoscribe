import 'dart:async';
import 'package:flutter/foundation.dart';

// No-op fallback for non-web platforms in Dreamflow preview.
class CrossAudioPlayer {
  final _controller = StreamController<bool>.broadcast();
  Stream<bool> get onPlayingChanged => _controller.stream;

  Future<void> playBytes(Uint8List bytes, {String? mimeType}) async {
    debugPrint('CrossAudioPlayer.stub: playBytes len=${bytes.length} mime=$mimeType');
    // Not implemented in preview; emit playing then immediately stopped
    _controller.add(true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    _controller.add(false);
  }

  Future<void> pause() async {
    debugPrint('CrossAudioPlayer.stub: pause');
    _controller.add(false);
  }

  Future<void> resume() async {
    debugPrint('CrossAudioPlayer.stub: resume');
    _controller.add(true);
  }

  Future<void> stop() async {
    debugPrint('CrossAudioPlayer.stub: stop');
    _controller.add(false);
  }
}
