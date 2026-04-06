import 'dart:convert';
import 'package:http/http.dart' as http;

/// OAuth2 password-grant token fetcher for EarthRanger image access.
/// Mirrors the Java EarthRangerAuth class.
class EarthRangerAuth {
  static String? _accessToken;
  static int _tokenExpiryMs = 0;

  final String username;
  final String password;

  EarthRangerAuth({required this.username, required this.password});

  /// Return cached token if still valid.
  static String? get cachedToken {
    if (_accessToken != null &&
        DateTime.now().millisecondsSinceEpoch < _tokenExpiryMs) {
      return _accessToken;
    }
    return null;
  }

  /// Fetch a fresh access token (or return cached one).
  Future<String?> getAccessToken() async {
    if (cachedToken != null) return _accessToken;

    try {
      final response = await http.post(
        Uri.parse('https://epictech.pamdas.org/oauth2/token/'),
        body: {
          'client_id': 'das_web_client',
          'grant_type': 'password',
          'username': username,
          'password': password,
        },
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        _accessToken = json['access_token'] as String;
        final expiresIn = (json['expires_in'] as num).toInt();
        _tokenExpiryMs =
            DateTime.now().millisecondsSinceEpoch + (expiresIn * 1000) - 60000;
        return _accessToken;
      }
    } catch (e) {
      // Silently fail – images will load without auth
    }
    return null;
  }

  /// Build auth headers for image loading.
  Map<String, String>? get authHeaders {
    final token = cachedToken;
    if (token == null) return null;
    return {'Authorization': 'Bearer $token'};
  }
}
