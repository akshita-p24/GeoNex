/// auth_service.dart
///
/// Manages JWT authentication state for GeoNex.
/// - Stores token in memory (SharedPreferences not yet added; using simple in-memory for now)
/// - Calls the FastAPI backend /auth/login and /auth/me
/// - Maps backend roles to Flutter UserRole
/// - Persists token across restarts using the local file cache
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../constants/app_constants.dart';
import '../models/user_profile.dart';

/// Backend base URL — change to your server IP / deployed URL
const String kBackendBaseUrl = 'http://10.0.2.2:8000';

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

  AuthSession? get session => _session;
  bool get isAuthenticated => _session != null;
  UserProfile? get currentUser => _session?.profile;
  String? get token => _session?.token;

  // ---------------------------------------------------------------------------
  // LOGIN
  // ---------------------------------------------------------------------------

  /// Calls POST /api/v1/auth/login with form-encoded credentials.
  /// Returns [AuthSession] on success, throws [AuthException] on failure.
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse('$kBackendBaseUrl/api/v1/auth/login');

    http.Response response;
    try {
      response = await http.post(
        uri,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'username': email,
          'password': password,
        },
      ).timeout(const Duration(seconds: 15));
    } catch (e) {
      throw AuthException('Cannot reach server. Check connection: $e');
    }

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final token = body['access_token'] as String;
      final userJson = body['user'] as Map<String, dynamic>;
      final profile = _parseUserProfile(userJson);

      _session = AuthSession(token: token, profile: profile);
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

    final uri = Uri.parse('$kBackendBaseUrl/api/v1/auth/me');
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
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // RESTORE SESSION (called on app start)
  // ---------------------------------------------------------------------------

  /// Restores a previous session from cached token if available.
  /// Since we don't have SharedPreferences yet, this is a no-op.
  Future<bool> restoreSession(String? cachedToken) async {
    if (cachedToken == null || cachedToken.isEmpty) return false;

    // Build a temporary session with the token and try to fetch profile
    _session = AuthSession(
      token: cachedToken,
      profile: const UserProfile(
        id: '',
        name: '',
        emailOrPhone: '',
        role: UserRole.citizen,
      ),
    );

    try {
      await fetchMe();
      return true;
    } catch (_) {
      _session = null;
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
