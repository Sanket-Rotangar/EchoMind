import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ApiService {
  static const String functionsBaseUrl =
      'https://nm5x7yfa.ap-southeast.insforge.app/functions';
  static const String appBaseUrl = 'https://nm5x7yfa.ap-southeast.insforge.app';
  static const String anonKey = String.fromEnvironment(
    'INSFORGE_ANON_KEY',
    defaultValue: '',
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
      Uri.parse('$functionsBaseUrl/storage-upload-url'),
      headers: _headers(),
    );

    if (uploadUrlResponse.statusCode != 200) {
      throw Exception('Failed to generate upload URL');
    }

    final uploadUrlPayload =
        jsonDecode(uploadUrlResponse.body) as Map<String, dynamic>;
    final uploadUrl = uploadUrlPayload['uploadUrl'] as String?;
    final path = uploadUrlPayload['path'] as String?;
    final method = (uploadUrlPayload['method'] as String?)?.toLowerCase();
    final fields = uploadUrlPayload['fields'] as Map<String, dynamic>?;
    final confirmRequired = uploadUrlPayload['confirmRequired'] == true;
    final confirmUrl = uploadUrlPayload['confirmUrl'] as String?;

    if (uploadUrl == null || path == null) {
      throw Exception('Invalid upload URL response');
    }

    final file = File(filePath);

    if (method == 'presigned' && fields != null && fields.isNotEmpty) {
      final uploadRequest = http.MultipartRequest('POST', Uri.parse(uploadUrl));

      fields.forEach((key, value) {
        uploadRequest.fields[key] = value.toString();
      });

      uploadRequest.files.add(
        await http.MultipartFile.fromPath('file', filePath),
      );

      final uploadStreamResponse = await uploadRequest.send();

      if (uploadStreamResponse.statusCode < 200 ||
          uploadStreamResponse.statusCode >= 300) {
        throw Exception('Failed to upload audio file');
      }
    } else {
      final bytes = await file.readAsBytes();
      final uploadResponse = await http.put(
        Uri.parse(uploadUrl),
        headers: {'Content-Type': 'audio/mp4'},
        body: bytes,
      );

      if (uploadResponse.statusCode < 200 || uploadResponse.statusCode >= 300) {
        throw Exception('Failed to upload audio file');
      }
    }

    if (confirmRequired && confirmUrl != null && confirmUrl.isNotEmpty) {
      if (anonKey.isEmpty) {
        throw Exception(
          'INSFORGE_ANON_KEY is required for upload confirmation',
        );
      }

      final confirmResponse = await http.post(
        Uri.parse('$appBaseUrl$confirmUrl'),
        headers: {
          ..._headers(contentType: 'application/json'),
          'Authorization': 'Bearer $anonKey',
        },
        body: jsonEncode({
          'size': await file.length(),
          'contentType': 'audio/mp4',
        }),
      );

      if (confirmResponse.statusCode < 200 ||
          confirmResponse.statusCode >= 300) {
        throw Exception('Failed to confirm audio upload');
      }
    }

    final processResponse = await http.post(
      Uri.parse('$functionsBaseUrl/audio-process'),
      headers: _headers(contentType: 'application/json'),
      body: jsonEncode({'path': path}),
    );

    if (processResponse.statusCode != 202) {
      throw Exception('Failed to process audio');
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
      Uri.parse('$functionsBaseUrl/meetings-list?offset=$offset&limit=$limit'),
      headers: _headers(),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch meetings');
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
      Uri.parse('$functionsBaseUrl/meeting-detail?id=$id'),
      headers: _headers(),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch meeting details');
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final data = payload['data'];

    if (data is! Map<String, dynamic>) {
      throw Exception('Invalid meeting details response format');
    }

    return data;
  }
}
