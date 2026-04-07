import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'config.dart';

class ApiService {
  static const Duration _requestTimeout = AppConfig.requestTimeout;

  static const String fastApiBaseUrl = AppConfig.backendUrl;

  static final AuthService _authService = AuthService();

  static Map<String, String> _headers({String? contentType}) {
    final user = _authService.currentUser;
    if (user == null) {
      throw Exception('Not authenticated. Please sign in.');
    }

    return _authService.getAuthHeaders(contentType: contentType);
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

  static Future<String> getCalendarAuthUrl() async {
    final response = await http.get(
      Uri.parse('$fastApiBaseUrl/auth/google/calendar/url'),
      headers: _headers(),
    ).timeout(_requestTimeout);

    if (response.statusCode != 200) {
      throw Exception(_extractErrorMessage(response, 'Failed to get calendar auth URL'));
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return payload['url'] as String;
  }

  static Future<void> disconnectCalendar() async {
    final response = await http.post(
      Uri.parse('$fastApiBaseUrl/auth/google/calendar/disconnect'),
      headers: _headers(),
    ).timeout(_requestTimeout);

    if (response.statusCode != 200) {
      throw Exception(_extractErrorMessage(response, 'Failed to disconnect calendar'));
    }
  }

  static Future<Map<String, dynamic>> sendChatMessage(String message) async {
    final response = await http.post(
      Uri.parse('$fastApiBaseUrl/api/v1/chat'),
      headers: _headers(contentType: 'application/json'),
      body: jsonEncode({'message': message}),
    ).timeout(const Duration(seconds: 60)); // Longer timeout for AI responses

    if (response.statusCode != 200) {
      throw Exception(_extractErrorMessage(response, 'Chat request failed'));
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return payload;
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
