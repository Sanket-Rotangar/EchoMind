import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// A temporary local HTTP server that listens for OAuth callbacks.
/// 
/// This is used for the "loopback redirect" OAuth flow where:
/// 1. App starts a local server on 127.0.0.1:port
/// 2. Google redirects to http://127.0.0.1:port/callback?code=...&state=...
/// 3. This server catches the redirect, extracts the code, and returns it
class OAuthCallbackServer {
  HttpServer? _server;
  final int port;
  final String path;
  
  OAuthCallbackServer({
    this.port = 8080,
    this.path = '/callback',
  });
  
  /// The redirect URI to use with Google OAuth
  String get redirectUri => 'http://127.0.0.1:$port$path';
  
  /// Start the server and wait for the OAuth callback.
  /// Returns a map with 'code' and 'state' on success, or 'error' on failure.
  /// Times out after [timeout] duration.
  Future<Map<String, String>> waitForCallback({
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final completer = Completer<Map<String, String>>();
    
    try {
      // Try to bind to the port
      _server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        port,
        shared: true,
      );
      
      debugPrint('OAuth callback server listening on $redirectUri');
      
      // Set up timeout
      final timer = Timer(timeout, () {
        if (!completer.isCompleted) {
          completer.completeError(TimeoutException('OAuth callback timeout'));
          stop();
        }
      });
      
      // Listen for requests
      _server!.listen((HttpRequest request) async {
        debugPrint('Received request: ${request.uri}');
        
        // Check if this is our callback path
        if (request.uri.path == path) {
          final code = request.uri.queryParameters['code'];
          final state = request.uri.queryParameters['state'];
          final error = request.uri.queryParameters['error'];
          
          // Send response to browser
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.html;
          
          if (error != null) {
            request.response.write(_errorHtml(error));
            await request.response.close();
            
            timer.cancel();
            if (!completer.isCompleted) {
              completer.complete({'error': error});
            }
          } else if (code != null && state != null) {
            request.response.write(_successHtml());
            await request.response.close();
            
            timer.cancel();
            if (!completer.isCompleted) {
              completer.complete({'code': code, 'state': state});
            }
          } else {
            request.response.write(_errorHtml('Missing code or state parameter'));
            await request.response.close();
          }
        } else {
          // Not our callback, return 404
          request.response.statusCode = HttpStatus.notFound;
          request.response.write('Not found');
          await request.response.close();
        }
      });
      
      return await completer.future;
    } catch (e) {
      debugPrint('OAuth callback server error: $e');
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
      rethrow;
    } finally {
      await stop();
    }
  }
  
  /// Stop the server
  Future<void> stop() async {
    if (_server != null) {
      debugPrint('Stopping OAuth callback server');
      await _server!.close(force: true);
      _server = null;
    }
  }
  
  String _successHtml() => '''
<!DOCTYPE html>
<html>
<head>
  <title>Authorization Successful</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      display: flex;
      justify-content: center;
      align-items: center;
      height: 100vh;
      margin: 0;
      background: #0D0D0D;
      color: #F5F5F5;
    }
    .container {
      text-align: center;
      padding: 40px;
    }
    .icon {
      font-size: 64px;
      margin-bottom: 20px;
      color: #4CAF50;
    }
    h1 {
      color: #E9A28B;
      margin-bottom: 16px;
    }
    p {
      color: #8A8A8A;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="icon">✓</div>
    <h1>Authorization Successful!</h1>
    <p>You can close this window and return to the app.</p>
  </div>
  <script>
    // Try to close the window after a short delay
    setTimeout(function() {
      window.close();
    }, 2000);
  </script>
</body>
</html>
''';

  String _errorHtml(String error) => '''
<!DOCTYPE html>
<html>
<head>
  <title>Authorization Failed</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      display: flex;
      justify-content: center;
      align-items: center;
      height: 100vh;
      margin: 0;
      background: #0D0D0D;
      color: #F5F5F5;
    }
    .container {
      text-align: center;
      padding: 40px;
    }
    .icon {
      font-size: 64px;
      margin-bottom: 20px;
      color: #f44336;
    }
    h1 {
      color: #E9A28B;
      margin-bottom: 16px;
    }
    p {
      color: #8A8A8A;
    }
    .error {
      background: #1A1A1A;
      padding: 12px;
      border-radius: 8px;
      margin-top: 16px;
      font-family: monospace;
      color: #f44336;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="icon">✗</div>
    <h1>Authorization Failed</h1>
    <p>Please close this window and try again in the app.</p>
    <div class="error">$error</div>
  </div>
</body>
</html>
''';
}
