import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'config.dart';
import 'oauth_callback_server.dart';

class User {
  final String id;
  final String email;
  final String? name;
  final String? photoUrl;
  final bool calendarConnected;

  User({
    required this.id,
    required this.email,
    this.name,
    this.photoUrl,
    this.calendarConnected = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'name': name,
    'photoUrl': photoUrl,
    'calendarConnected': calendarConnected,
  };

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] ?? '',
    email: json['email'] ?? '',
    name: json['name'],
    photoUrl: json['photoUrl'],
    calendarConnected: json['calendarConnected'] ?? false,
  );
}

class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  static const String _userKey = 'current_user';
  static const String _tokenKey = 'auth_token';

  User? _currentUser;
  String? _authToken;
  bool _isLoading = false;
  
  // OAuth callback server for loopback redirect
  OAuthCallbackServer? _oauthServer;
  
  // Callback for OAuth completion
  void Function(bool success, String? error)? onCalendarOAuthComplete;

  User? get currentUser => _currentUser;
  String? get authToken => _authToken;
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    // Use the Android client ID for sign-in
    // The serverClientId is the Web client ID for getting ID tokens that the backend can verify
    serverClientId: '892230117968-s3n9bugmvj04n8dfb9056vc0gc2ve0p3.apps.googleusercontent.com',
    scopes: [
      'email',
      'profile',
    ],
  );

  // Backend URL - uses centralized config
  static const String backendUrl = AppConfig.backendUrl;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(_userKey);
    final token = prefs.getString(_tokenKey);

    if (userJson != null && token != null) {
      try {
        _currentUser = User.fromJson(jsonDecode(userJson));
        _authToken = token;
        notifyListeners();
      } catch (e) {
        debugPrint('Error loading user from prefs: $e');
        await _clearStorage();
      }
    }
  }
  
  /// Start the Google Calendar OAuth flow using loopback redirect.
  /// 
  /// This method:
  /// 1. Starts a local HTTP server to catch the OAuth callback
  /// 2. Opens the Google authorization URL in the browser
  /// 3. Waits for Google to redirect back to the local server
  /// 4. Sends the authorization code to the backend to exchange for tokens
  Future<void> connectGoogleCalendar() async {
    if (_currentUser == null || _authToken == null) {
      onCalendarOAuthComplete?.call(false, 'Not logged in');
      return;
    }
    
    // Create OAuth callback server using config values
    _oauthServer = OAuthCallbackServer(
      port: AppConfig.oauthCallbackPort,
      path: AppConfig.oauthCallbackPath,
    );
    final redirectUri = _oauthServer!.redirectUri;
    
    try {
      // Get the authorization URL from the backend, passing our redirect URI
      final authUrlResponse = await http.get(
        Uri.parse('$backendUrl/auth/google/calendar/url?redirect_uri=${Uri.encodeComponent(redirectUri)}'),
        headers: {
          'x-user-id': _currentUser!.id,
          'Authorization': 'Bearer $_authToken',
        },
      );
      
      if (authUrlResponse.statusCode != 200) {
        throw Exception('Failed to get authorization URL');
      }
      
      final authUrlData = jsonDecode(authUrlResponse.body);
      final authUrl = authUrlData['url'] as String;
      
      debugPrint('Starting OAuth flow with redirect URI: $redirectUri');
      debugPrint('Auth URL: $authUrl');
      
      // Start listening for callback BEFORE opening browser
      final callbackFuture = _oauthServer!.waitForCallback(
        timeout: const Duration(minutes: 5),
      );
      
      // Open the authorization URL in the browser
      final launched = await launchUrl(
        Uri.parse(authUrl),
        mode: LaunchMode.externalApplication,
      );
      
      if (!launched) {
        throw Exception('Could not open browser');
      }
      
      // Wait for the callback
      final result = await callbackFuture;
      
      if (result.containsKey('error')) {
        throw Exception(result['error']);
      }
      
      final code = result['code']!;
      final state = result['state']!;
      
      debugPrint('Received OAuth callback with code');
      
      // Send the code to the backend to exchange for tokens
      final tokenResponse = await http.post(
        Uri.parse('$backendUrl/auth/google/calendar/callback'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_authToken',
        },
        body: jsonEncode({
          'code': code,
          'state': state,
          'redirect_uri': redirectUri,
        }),
      );
      
      if (tokenResponse.statusCode == 200) {
        debugPrint('Calendar connected successfully!');
        await refreshCalendarStatus();
        onCalendarOAuthComplete?.call(true, null);
      } else {
        final errorData = jsonDecode(tokenResponse.body);
        final errorMessage = errorData['detail'] ?? 'Failed to connect calendar';
        throw Exception(errorMessage);
      }
    } catch (e) {
      debugPrint('OAuth error: $e');
      onCalendarOAuthComplete?.call(false, e.toString());
    } finally {
      await _oauthServer?.stop();
      _oauthServer = null;
    }
  }
  
  void disposeOAuthServer() {
    _oauthServer?.stop();
    _oauthServer = null;
  }

  Future<bool> signInWithGoogle() async {
    try {
      _isLoading = true;
      notifyListeners();

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;

      if (idToken == null) {
        throw Exception('Failed to get ID token from Google');
      }

      // Send token to backend
      final response = await http.post(
        Uri.parse('$backendUrl/auth/google'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id_token': idToken}),
      );

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body);
        throw Exception(error['detail'] ?? 'Authentication failed');
      }

      final data = jsonDecode(response.body);
      
      _currentUser = User(
        id: data['user']['id'],
        email: data['user']['email'],
        name: data['user']['name'],
        photoUrl: googleUser.photoUrl,
        calendarConnected: data['user']['calendar_connected'] ?? false,
      );
      _authToken = data['access_token'];

      await _saveToStorage();

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Google Sign In Error: $e');
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<bool> registerWithEmail({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();

      final response = await http.post(
        Uri.parse('$backendUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'name': name,
        }),
      );

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body);
        throw Exception(error['detail'] ?? 'Registration failed');
      }

      final data = jsonDecode(response.body);
      
      _currentUser = User(
        id: data['user']['id'],
        email: data['user']['email'],
        name: data['user']['name'],
        calendarConnected: data['user']['calendar_connected'] ?? false,
      );
      _authToken = data['access_token'];

      await _saveToStorage();

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Registration Error: $e');
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<bool> loginWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();

      final response = await http.post(
        Uri.parse('$backendUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body);
        throw Exception(error['detail'] ?? 'Login failed');
      }

      final data = jsonDecode(response.body);
      
      _currentUser = User(
        id: data['user']['id'],
        email: data['user']['email'],
        name: data['user']['name'],
        calendarConnected: data['user']['calendar_connected'] ?? false,
      );
      _authToken = data['access_token'];

      await _saveToStorage();

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Login Error: $e');
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      debugPrint('Google sign out error: $e');
    }

    _currentUser = null;
    _authToken = null;
    await _clearStorage();
    notifyListeners();
  }

  Future<void> refreshCalendarStatus() async {
    if (_currentUser == null || _authToken == null) return;

    try {
      final response = await http.get(
        Uri.parse('$backendUrl/api/v1/user/profile'),
        headers: {
          'Authorization': 'Bearer $_authToken',
          'x-user-id': _currentUser!.id,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _currentUser = User(
          id: _currentUser!.id,
          email: _currentUser!.email,
          name: _currentUser!.name,
          photoUrl: _currentUser!.photoUrl,
          calendarConnected: data['calendar_connected'] ?? false,
        );
        await _saveToStorage();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error refreshing calendar status: $e');
    }
  }

  Future<void> _saveToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    if (_currentUser != null) {
      await prefs.setString(_userKey, jsonEncode(_currentUser!.toJson()));
    }
    if (_authToken != null) {
      await prefs.setString(_tokenKey, _authToken!);
    }
  }

  Future<void> _clearStorage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    await prefs.remove(_tokenKey);
  }

  Map<String, String> getAuthHeaders({String? contentType}) {
    final headers = <String, String>{};
    
    if (_currentUser != null) {
      headers['x-user-id'] = _currentUser!.id;
    }
    if (_authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    if (contentType != null) {
      headers['Content-Type'] = contentType;
    }
    
    return headers;
  }
}
