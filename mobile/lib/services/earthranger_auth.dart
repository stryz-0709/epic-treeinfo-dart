import 'dart:convert';
import 'package:http/http.dart' as http;

/// EarthRanger token helper for image access.
///
/// Security baseline:
/// - direct password grant is disabled by default
/// - mobile app must not require embedded ER credentials for normal operation
class EarthRangerAuth {
  static String? _accessToken;
  static int _tokenExpiryMs = 0;

  final bool enablePasswordGrant;
  final String oauthTokenUrl;
  final Set<String> allowedOauthHosts;
  final String username;
  final String password;

  EarthRangerAuth({
    this.enablePasswordGrant = false,
    this.oauthTokenUrl = 'https://epictech.pamdas.org/oauth2/token/',
    Set<String>? allowedOauthHosts,
    this.username = '',
    this.password = '',
  }) : allowedOauthHosts = (allowedOauthHosts ?? {'epictech.pamdas.org'})
            .map((e) => e.toLowerCase())
            .toSet();

  bool _isTrustedTokenEndpoint() {
    final uri = Uri.tryParse(oauthTokenUrl);
    if (uri == null) return false;
    if (uri.scheme.toLowerCase() != 'https') return false;
    return allowedOauthHosts.contains(uri.host.toLowerCase());
  }

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

    if (!enablePasswordGrant) {
      return null;
    }

    if (!_isTrustedTokenEndpoint()) {
      return null;
    }

    if (username.isEmpty || password.isEmpty) {
      return null;
    }

    try {
      final response = await http.post(
        Uri.parse(oauthTokenUrl),
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
