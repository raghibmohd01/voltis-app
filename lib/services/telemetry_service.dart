import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/telemetry.dart';
import '../config.dart';

class TelemetryService {
  final String _endpoint;

  TelemetryService({String? endpoint}) : _endpoint = endpoint ?? telemetryEndpoint;

  Future<Telemetry> fetchTelemetry() async {
    try {
      final response = await http
          .get(Uri.parse(_endpoint))
          .timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return Telemetry.fromJson(json);
      } else {
        throw Exception('Server returned ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to fetch telemetry: $e');
    }
  }
}
