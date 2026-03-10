// A tiny cross-platform audio player abstraction.
// - On web: implemented with HTMLAudioElement (no plugins)
// - On Android/iOS: implemented with audioplayers via IO backend

export 'cross_audio_player_web.dart' if (dart.library.io) 'cross_audio_player_io.dart';
