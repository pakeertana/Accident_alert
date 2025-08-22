import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

class DetectionService {
  final String serverUrl; // e.g. "http://192.168.0.10:8000"
  DetectionService(this.serverUrl);

  Future<List<Map<String, dynamic>>> sendImage(File imageFile) async {
    var uri = Uri.parse('$serverUrl/detect');
    var req = http.MultipartRequest('POST', uri);
    req.files.add(await http.MultipartFile.fromPath('file', imageFile.path));
    var streamed = await req.send();
    var resp = await http.Response.fromStream(streamed);
    if (resp.statusCode == 200) {
      final body = jsonDecode(resp.body);
      final List detections = body['detections'] ?? [];
      return detections.map((d) => Map<String, dynamic>.from(d)).toList();
    } else {
      throw Exception('Server error ${resp.statusCode}: ${resp.body}');
    }
  }
}
