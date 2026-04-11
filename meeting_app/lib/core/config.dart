/// Centralized configuration for the EchoMind app.
/// 
/// Backend URL can be overridden at build time using:
/// ```
/// flutter run --dart-define=FASTAPI_BASE_URL=https://echomind-tvw1.onrender.com
/// ```
/// 
/// For local testing, set a LAN URL either:
/// 1. Via --dart-define flag when running
/// 2. Or update the defaultValue below temporarily
class AppConfig {
  AppConfig._();

  /// Default backend URL.
  /// Uses live Render backend by default; no explicit port is needed for HTTPS.
  static const String _defaultBackendUrl = 'https://echomind-tvw1.onrender.com';

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
