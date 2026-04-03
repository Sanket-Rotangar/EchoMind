import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ApiService {
  static const Duration _requestTimeout = Duration(seconds: 30);

  static const String fastApiBaseUrl = String.fromEnvironment(
    'FASTAPI_BASE_URL',
    defaultValue: 'http://192.168.1.13:8000', // Safe default fallback
  );

  static const String userId = String.fromEnvironment(
    'SOORA_USER_ID',
    defaultValue: '',
  );

  static Map<String, String> _headers({String? contentType}) {
    if (userId.isEmpty) {
      throw Exception('SOORA_USER_ID is required for API requests');
    }

    return {
      'x-user-id': userId,
      if (contentType != null) 'Content-Type': contentType,
    };
  }

  static Future<Map<String, dynamic>> processMeetingAudio(
    String filePath,
  ) async {
    final uploadUrlResponse = await http.get(
      Uri.parse('$fastApiBaseUrl/api/v1/storage/upload-url'),
      headers: _headers(),
    ).timeout(_requestTimeout);

    if (uploadUrlResponse.statusCode != 200) {
      throw Exception(_extractErrorMessage(uploadUrlResponse, 'Failed to generate upload URL'));
    }

    final uploadUrlPayload =
        jsonDecode(uploadUrlResponse.body) as Map<String, dynamic>;
    final uploadUrl = uploadUrlPayload['uploadUrl'] as String?;
    final path = uploadUrlPayload['path'] as String?;

    if (uploadUrl == null || path == null) {
      throw Exception('Invalid upload URL response');
    }

    final file = File(filePath);

    final bytes = await file.readAsBytes();
    final uploadResponse = await http.put(
      Uri.parse(uploadUrl),
      headers: {'Content-Type': 'audio/mp4'},
      body: bytes,
    ).timeout(_requestTimeout);

    if (uploadResponse.statusCode < 200 || uploadResponse.statusCode >= 300) {
      throw Exception('Failed to upload audio file');
    }

    final processResponse = await http.post(
      Uri.parse('$fastApiBaseUrl/api/meetings/process'),
      headers: _headers(contentType: 'application/json'),
      body: jsonEncode({'path': path}),
    ).timeout(_requestTimeout);

    if (processResponse.statusCode != 202) {
      throw Exception(_extractErrorMessage(processResponse, 'Failed to process audio'));
    }

    final payload = jsonDecode(processResponse.body) as Map<String, dynamic>;

    if (payload['success'] != true || payload['meetingId'] == null) {
      throw Exception('Invalid processing response format');
    }

    return payload;
  }

  static Future<List<dynamic>> getMeetings({
    int offset = 0,
    int limit = 8,
  }) async {
    final response = await http.get(
      Uri.parse('$fastApiBaseUrl/api/v1/meetings?offset=$offset&limit=$limit'),
      headers: _headers(),
    ).timeout(_requestTimeout);

    if (response.statusCode != 200) {
      throw Exception(_extractErrorMessage(response, 'Failed to fetch meetings'));
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final data = payload['data'];

    if (data is! List) {
      throw Exception('Invalid meetings response format');
    }

    return data;
  }

  static Future<Map<String, dynamic>> getMeetingDetails(String id) async {
    final response = await http.get(
      Uri.parse('$fastApiBaseUrl/api/v1/meetings/$id'),
      headers: _headers(),
    ).timeout(_requestTimeout);

    if (response.statusCode != 200) {
      throw Exception(_extractErrorMessage(response, 'Failed to fetch meeting details'));
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final data = payload['data'];

    if (data is! Map<String, dynamic>) {
      throw Exception('Invalid meeting details response format');
    }

    return data;
  }

  static String _extractErrorMessage(http.Response response, String fallback) {
    try {
      final payload = jsonDecode(response.body);
      if (payload is Map<String, dynamic>) {
        final detail = payload['detail'];
        if (detail is String && detail.isNotEmpty) {
          return detail;
        }
        final message = payload['message'];
        if (message is String && message.isNotEmpty) {
          return message;
        }
      }
    } catch (_) {}
    return '$fallback (HTTP ${response.statusCode})';
  }
}
