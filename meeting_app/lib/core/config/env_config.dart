import 'package:flutter_dotenv/flutter_dotenv.dart';

final class EnvConfig {
  EnvConfig._();

  static Future<void> load() async {
    await dotenv.load(fileName: '.env');
  }

  static String get apiBaseUrl => _read('API_BASE_URL');
  static String get supabaseUrl => _read('SUPABASE_URL');
  static String get supabaseAnonKey => _read('SUPABASE_ANON_KEY');

  static String _read(String key) {
    final value = dotenv.env[key];
    if (value == null || value.trim().isEmpty) {
      throw StateError('Missing required env variable: $key');
    }
    return value;
  }
}
