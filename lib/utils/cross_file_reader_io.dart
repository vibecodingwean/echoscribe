// VM/Device implementation using dart:io to read file bytes
// Note: This file is only compiled on IO platforms via conditional import.
import 'dart:io';

Future<List<int>> readAllBytesCross(String pathOrUrl) async {
  final file = File(pathOrUrl);
  return await file.readAsBytes();
}
