/// Centralized configuration for the EchoMind app.
/// 
/// Backend URL can be overridden at build time using:
/// ```
/// flutter run --dart-define=FASTAPI_BASE_URL=http://your-ip:8000
/// ```
/// 
/// When changing WiFi networks, update the IP either:
/// 1. Via --dart-define flag when running
/// 2. Or update the defaultValue below for development
class AppConfig {
  AppConfig._();

  /// Default backend URL for development.
  /// Update this when your local IP changes.
  static const String _defaultBackendUrl = 'http://192.168.100.190:8000';

  /// Backend API base URL.
  /// Uses compile-time environment variable if provided, otherwise falls back to default.
  static const String backendUrl = String.fromEnvironment(
    'FASTAPI_BASE_URL',
    defaultValue: _defaultBackendUrl,
  );

  /// OAuth callback server port for loopback redirect flow.
  static const int oauthCallbackPort = 8085;

  /// OAuth callback path.
  static const String oauthCallbackPath = '/callback';

  /// Request timeout duration.
  static const Duration requestTimeout = Duration(seconds: 30);
}
