/// auth_service.dart
///
/// Manages JWT authentication state for GeoNex.
/// - Stores session securely in local app storage
/// - Calls the FastAPI backend /auth/login, /auth/register, and /auth/me
/// - Maps backend roles to Flutter UserRole
/// - Persists token across restarts using local session file
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../constants/app_constants.dart';
import '../models/user_profile.dart';

/// Backend base URL — configured for Android testing over LAN
String kBackendBaseUrl = 'http://10.235.29.64:8000';

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => 'AuthException: $message';
}

/// Holds the current auth session.
class AuthSession {
  final String token;
  final UserProfile profile;

  const AuthSession({required this.token, required this.profile});
}

/// Singleton auth service.
class AuthService extends ChangeNotifier {
  AuthSession? _session;
  String _baseUrl = kBackendBaseUrl;

  AuthSession? get session => _session;
  bool get isAuthenticated => _session != null;
  UserProfile? get currentUser => _session?.profile;
  String? get token => _session?.token;

  String get baseUrl => _baseUrl;
  set baseUrl(String url) {
    _baseUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    kBackendBaseUrl = _baseUrl;
    notifyListeners();
  }

  File _getSessionStorageFile() {
    final tempDir = Directory.systemTemp;
    return File('${tempDir.path}/geonex_auth_session.json');
  }

  // ---------------------------------------------------------------------------
  // REGISTER
  // ---------------------------------------------------------------------------

  /// Calls POST /api/v1/auth/register with user information.
  /// Throws [AuthException] on failure.
  Future<UserProfile> register({
    required String email,
    required String password,
    required String fullName,
    String role = 'CITIZEN',
  }) async {
    final uri = Uri.parse('$_baseUrl/api/v1/auth/register');

    http.Response response;
    try {
      response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email.trim(),
          'password': password,
          'full_name': fullName.trim(),
          'role': role,
        }),
      ).timeout(const Duration(seconds: 15));
    } catch (e) {
      throw AuthException('Cannot reach server ($_baseUrl). Check connection: $e');
    }

    if (response.statusCode == 201 || response.statusCode == 200) {
      final userJson = jsonDecode(response.body) as Map<String, dynamic>;
      return _parseUserProfile(userJson);
    } else {
      final body = _tryDecodeBody(response.body);
      throw AuthException('Registration failed (${response.statusCode}): $body');
    }
  }

  // ---------------------------------------------------------------------------
  // LOGIN
  // ---------------------------------------------------------------------------

  /// Calls POST /api/v1/auth/login with form-encoded credentials.
  /// Returns [AuthSession] on success, throws [AuthException] on failure.
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/v1/auth/login');

    http.Response response;
    try {
      response = await http.post(
        uri,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'username': email.trim(),
          'password': password,
        },
      ).timeout(const Duration(seconds: 15));
    } catch (e) {
      throw AuthException('Cannot reach server ($_baseUrl). Check connection: $e');
    }

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final token = body['access_token'] as String;
      final userJson = body['user'] as Map<String, dynamic>;
      final profile = _parseUserProfile(userJson);

      _session = AuthSession(token: token, profile: profile);
      await _persistSession(token, userJson);
      notifyListeners();
      return _session!;
    } else if (response.statusCode == 401) {
      throw const AuthException('Incorrect email or password.');
    } else {
      final body = _tryDecodeBody(response.body);
      throw AuthException('Login failed (${response.statusCode}): $body');
    }
  }

  // ---------------------------------------------------------------------------
  // FETCH ME
  // ---------------------------------------------------------------------------

  /// Fetches current user profile using the stored JWT.
  Future<UserProfile> fetchMe() async {
    final t = _session?.token;
    if (t == null) throw const AuthException('Not authenticated.');

    final uri = Uri.parse('$_baseUrl/api/v1/auth/me');
    http.Response response;
    try {
      response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $t'},
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      throw AuthException('Network error: $e');
    }

    if (response.statusCode == 200) {
      final userJson = jsonDecode(response.body) as Map<String, dynamic>;
      final profile = _parseUserProfile(userJson);
      _session = AuthSession(token: t, profile: profile);
      await _persistSession(t, userJson);
      notifyListeners();
      return profile;
    } else if (response.statusCode == 401) {
      logout();
      throw const AuthException('Session expired. Please log in again.');
    } else {
      throw AuthException('Failed to fetch profile: ${response.statusCode}');
    }
  }

  // ---------------------------------------------------------------------------
  // LOGOUT
  // ---------------------------------------------------------------------------

  void logout() {
    _session = null;
    _clearPersistedSession();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // SESSION PERSISTENCE (across app restarts)
  // ---------------------------------------------------------------------------

  Future<void> _persistSession(String token, Map<String, dynamic> userJson) async {
    try {
      final file = _getSessionStorageFile();
      final data = jsonEncode({
        'token': token,
        'user': userJson,
        'saved_at': DateTime.now().toIso8601String(),
      });
      await file.writeAsString(data);
    } catch (_) {}
  }

  Future<void> _clearPersistedSession() async {
    try {
      final file = _getSessionStorageFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  /// Restores a previously saved session on app startup.
  Future<bool> restoreSavedSession() async {
    try {
      final file = _getSessionStorageFile();
      if (!await file.exists()) return false;

      final content = await file.readAsString();
      if (content.isEmpty) return false;

      final data = jsonDecode(content) as Map<String, dynamic>;
      final token = data['token'] as String?;
      final userJson = data['user'] as Map<String, dynamic>?;

      if (token == null || token.isEmpty || userJson == null) {
        return false;
      }

      final profile = _parseUserProfile(userJson);
      _session = AuthSession(token: token, profile: profile);
      notifyListeners();

      // Validate token with backend in background
      try {
        await fetchMe();
        return true;
      } catch (e) {
        if (e is AuthException && e.message.contains('expired')) {
          _session = null;
          await _clearPersistedSession();
          notifyListeners();
          return false;
        }
        // In case of temporary network issue, keep current session
        return true;
      }
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  UserProfile _parseUserProfile(Map<String, dynamic> json) {
    final backendRole = (json['role'] as String? ?? 'CITIZEN').toUpperCase();
    final flutterRole = _mapRole(backendRole);

    return UserProfile(
      id: json['id']?.toString() ?? '',
      name: json['full_name'] as String? ?? 'Unknown',
      emailOrPhone: json['email'] as String? ?? '',
      role: flutterRole,
      designation: _designationForRole(flutterRole),
      assignedRegion: 'NER — Arunachal Pradesh',
      badgeNumber: _badgeForRole(backendRole, json['id']?.toString() ?? ''),
    );
  }

  UserRole _mapRole(String backendRole) {
    switch (backendRole) {
      case 'FIELD_OFFICER':
        return UserRole.fieldOfficer;
      case 'ADMIN':
      case 'DISTRICT_ADMIN':
        return UserRole.authority;
      case 'CITIZEN':
      default:
        return UserRole.citizen;
    }
  }

  String _designationForRole(UserRole role) {
    switch (role) {
      case UserRole.authority:
        return 'Authority — Disaster Management';
      case UserRole.fieldOfficer:
        return 'Field Officer — Rapid Response';
      case UserRole.citizen:
        return 'Verified Community Reporter';
    }
  }

  String _badgeForRole(String backendRole, String id) {
    final shortId = id.length >= 6 ? id.substring(0, 6).toUpperCase() : id.toUpperCase();
    switch (backendRole) {
      case 'FIELD_OFFICER':
        return 'FO-AR-$shortId';
      case 'ADMIN':
      case 'DISTRICT_ADMIN':
        return 'SDMA-NER-$shortId';
      default:
        return 'CITIZEN-NER-$shortId';
    }
  }

  String _tryDecodeBody(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      return (json['detail'] ?? json['message'] ?? body).toString();
    } catch (_) {
      return body;
    }
  }
}
