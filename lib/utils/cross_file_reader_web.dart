import 'package:http/http.dart' as http;

// Web: read bytes from a blob: or http(s) URL using http.readBytes
Future<List<int>> readAllBytesCross(String pathOrUrl) async {
  final uri = Uri.parse(pathOrUrl);
  return await http.readBytes(uri);
}
