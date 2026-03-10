// Stub implementation used if no platform-specific implementation is selected.
// Do not import this directly; import cross_file_reader.dart

Future<List<int>> readAllBytesCross(String pathOrUrl) async {
  throw UnsupportedError('readAllBytesCross is not supported on this platform');
}
