// Cross-platform file reader that returns bytes for both web (blob/http URLs)
// and IO platforms (file paths). Use conditional imports to select the right impl.



export 'cross_file_reader_stub.dart'
  if (dart.library.io) 'cross_file_reader_io.dart'
  if (dart.library.html) 'cross_file_reader_web.dart';
