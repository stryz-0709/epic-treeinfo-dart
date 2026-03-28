import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/mobile_api_service.dart';

/// Simple admin-only auth provider (mirrors the Java hardcoded admin login).
class AuthProvider extends ChangeNotifier {
  static const String _configuredAdminUsername =
      String.fromEnvironment('EARTHRANGER_ADMIN_USERNAME');
  static const String _configuredAdminPassword =
      String.fromEnvironment('EARTHRANGER_ADMIN_PASSWORD');
  static const String _prefRememberMe = 'mobile_auth_remember_me';
  static const String _prefAccessToken = 'mobile_auth_access_token';
  static const String _prefRefreshToken = 'mobile_auth_refresh_token';
  static const String _prefRole = 'mobile_auth_role';
  static const String _prefUsername = 'mobile_auth_username';
  static const String _prefDisplayName = 'mobile_auth_display_name';

  bool _isAdmin = false;
  bool _isLoading = false;
  bool _isRestoringSession = false;
  bool _restoreAttempted = false;
  bool _rememberMe = false;
  String? _error;
  String? _mobileAccessToken;
  String? _mobileRefreshToken;
  String? _mobileRole;
  String? _mobileUsername;
  String? _mobileDisplayName;
  int _authOperationId = 0;

  bool get isAdmin => _isAdmin;
  bool get isLoading => _isLoading;
  bool get isRestoringSession => _isRestoringSession;
  bool get restoreAttempted => _restoreAttempted;
  bool get rememberMe => _rememberMe;
  String? get error => _error;
  String? get mobileAccessToken => _mobileAccessToken;
  String? get mobileRefreshToken => _mobileRefreshToken;
  String? get mobileRole => _mobileRole;
  String? get mobileUsername => _mobileUsername;
  String? get mobileDisplayName => _mobileDisplayName;

  bool get hasMobileAccessToken {
    final token = _mobileAccessToken?.trim();
    return token != null && token.isNotEmpty;
  }

  bool get isLeaderSession => _mobileRole == 'leader' && hasMobileAccessToken;
  bool get isRangerSession => _mobileRole == 'ranger' && hasMobileAccessToken;
  bool get isAuthenticated => isLeaderSession || isRangerSession;

  int _startAuthOperation() {
    _authOperationId += 1;
    return _authOperationId;
  }

  bool _isCurrentAuthOperation(int operationId) {
    return operationId == _authOperationId;
  }

  void debugSetAdminForTesting(bool isAdmin) {
    assert(() {
      _isAdmin = isAdmin;
      return true;
    }());
  }

  /// Attempt admin login with compile-time configured credentials.
  bool login(String username, String password) {
    _startAuthOperation();
    _isLoading = true;
    _error = null;
    _isAdmin = false;
    clearMobileSession(notify: false);
    notifyListeners();

    final hasConfiguredCredentials =
        _configuredAdminUsername.isNotEmpty && _configuredAdminPassword.isNotEmpty;

    final success =
        hasConfiguredCredentials &&
        username == _configuredAdminUsername &&
        password == _configuredAdminPassword;

    if (!success) {
      _error = hasConfiguredCredentials ? 'login_failed' : 'login_not_configured';
    } else {
      _isAdmin = true;
    }

    _isLoading = false;
    notifyListeners();
    return success;
  }

  void logout() {
    _startAuthOperation();
    _isAdmin = false;
    _error = null;
    clearMobileSession(notify: false);
    notifyListeners();
  }

  Future<void> setRememberMe(bool value) async {
    _rememberMe = value;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefRememberMe, value);
  }

  Future<bool> loginWithMobileApi({
    required MobileAuthApi authApi,
    required String username,
    required String password,
    required bool rememberMe,
  }) async {
    final operationId = _startAuthOperation();

    _isLoading = true;
    _error = null;
    _isAdmin = false;
    clearMobileSession(notify: false);
    notifyListeners();

    final normalizedUsername = username.trim();
    final normalizedPassword = password;

    try {
      final session = await authApi.loginMobile(
        username: normalizedUsername,
        password: normalizedPassword,
      );

      if (!_isCurrentAuthOperation(operationId)) {
        return false;
      }

      var resolvedRole = session.role;
      var resolvedUsername = session.username ?? normalizedUsername;
      var resolvedDisplayName = session.displayName?.trim();
      if (resolvedDisplayName != null && resolvedDisplayName.isEmpty) {
        resolvedDisplayName = null;
      }

      try {
        final identity = await authApi.fetchCurrentMobileUser(
          accessToken: session.accessToken,
        );

        if (!_isCurrentAuthOperation(operationId)) {
          return false;
        }

        if (identity.role.trim().isNotEmpty) {
          resolvedRole = identity.role.trim().toLowerCase();
        }
        if (identity.username.trim().isNotEmpty) {
          resolvedUsername = identity.username.trim();
        }
        if (identity.displayName.trim().isNotEmpty) {
          resolvedDisplayName = identity.displayName.trim();
        }
      } catch (_) {
        // Best-effort identity enrichment. Login is still valid without /me.
      }

      setMobileSession(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
        role: resolvedRole,
        username: resolvedUsername,
        displayName: resolvedDisplayName,
      );

      if (!_isCurrentAuthOperation(operationId)) {
        return false;
      }

      _rememberMe = rememberMe;
      _restoreAttempted = true;

      final prefs = await SharedPreferences.getInstance();
      if (!_isCurrentAuthOperation(operationId)) {
        return false;
      }

      if (rememberMe) {
        await _persistRememberedSession(
          prefs: prefs,
          accessToken: session.accessToken,
          refreshToken: session.refreshToken,
          role: resolvedRole,
          username: resolvedUsername,
          displayName: resolvedDisplayName,
          rememberMe: rememberMe,
        );
      } else {
        await _clearPersistedMobileSession(
          prefs: prefs,
          clearRememberPreference: false,
        );
        await prefs.setBool(_prefRememberMe, false);
      }

      if (!_isCurrentAuthOperation(operationId)) {
        return false;
      }

      _isLoading = false;
      _error = null;
      notifyListeners();
      return true;
    } on MobileApiException catch (apiError) {
      if (_isCurrentAuthOperation(operationId)) {
        _isAdmin = false;
        clearMobileSession(notify: false);
        _error = apiError.statusCode == 401
            ? 'invalid_credentials'
            : 'network_error_try_again';
      }
    } catch (_) {
      if (_isCurrentAuthOperation(operationId)) {
        _isAdmin = false;
        clearMobileSession(notify: false);
        _error = 'network_error_try_again';
      }
    }

    if (_isCurrentAuthOperation(operationId)) {
      _isLoading = false;
      notifyListeners();
    }

    return false;
  }

  Future<void> restoreRememberedSession({
    required MobileAuthApi authApi,
  }) async {
    if (_restoreAttempted || _isRestoringSession) {
      return;
    }

    final operationId = _startAuthOperation();

    _isRestoringSession = true;
    _error = null;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      if (!_isCurrentAuthOperation(operationId)) {
        return;
      }

      final remember = prefs.getBool(_prefRememberMe) ?? false;
      _rememberMe = remember;

      if (!remember) {
        if (!_isCurrentAuthOperation(operationId)) {
          return;
        }
        await _clearPersistedMobileSession(
          prefs: prefs,
          clearRememberPreference: false,
        );
        clearMobileSession(notify: false);
        return;
      }

      final refreshToken = (prefs.getString(_prefRefreshToken) ?? '').trim();
      if (refreshToken.isEmpty) {
        if (!_isCurrentAuthOperation(operationId)) {
          return;
        }
        await _clearPersistedMobileSession(
          prefs: prefs,
          clearRememberPreference: false,
        );
        clearMobileSession(notify: false);
        return;
      }

      try {
        final refreshed = await authApi.refreshMobileSession(
          refreshToken: refreshToken,
        );

        if (!_isCurrentAuthOperation(operationId)) {
          return;
        }

        var resolvedRole = refreshed.role;
        var resolvedUsername =
            refreshed.username ?? (prefs.getString(_prefUsername) ?? '').trim();
        var resolvedDisplayName =
            (prefs.getString(_prefDisplayName) ?? '').trim();
        if (resolvedDisplayName.isEmpty) {
          resolvedDisplayName = refreshed.displayName?.trim() ?? '';
        }

        try {
          final identity = await authApi.fetchCurrentMobileUser(
            accessToken: refreshed.accessToken,
          );

          if (!_isCurrentAuthOperation(operationId)) {
            return;
          }

          if (identity.role.trim().isNotEmpty) {
            resolvedRole = identity.role.trim().toLowerCase();
          }
          if (identity.username.trim().isNotEmpty) {
            resolvedUsername = identity.username.trim();
          }
          if (identity.displayName.trim().isNotEmpty) {
            resolvedDisplayName = identity.displayName.trim();
          }
        } catch (_) {
          // Best-effort identity enrichment after refresh.
        }

        final normalizedDisplayName = resolvedDisplayName.trim();

        setMobileSession(
          accessToken: refreshed.accessToken,
          refreshToken: refreshed.refreshToken,
          role: resolvedRole,
          username: resolvedUsername,
          displayName: normalizedDisplayName.isEmpty
              ? null
              : normalizedDisplayName,
        );

        if (!_isCurrentAuthOperation(operationId)) {
          return;
        }

        await _persistRememberedSession(
          prefs: prefs,
          accessToken: refreshed.accessToken,
          refreshToken: refreshed.refreshToken,
          role: resolvedRole,
          username: resolvedUsername,
          displayName: normalizedDisplayName.isEmpty
              ? null
              : normalizedDisplayName,
          rememberMe: true,
        );
      } catch (_) {
        if (_isCurrentAuthOperation(operationId)) {
          _isAdmin = false;
          clearMobileSession(notify: false);
          await _clearPersistedMobileSession(
            prefs: prefs,
            clearRememberPreference: false,
          );
        }
      }
    } finally {
      if (_isCurrentAuthOperation(operationId)) {
        _restoreAttempted = true;
        _isRestoringSession = false;
        notifyListeners();
      } else {
        _isRestoringSession = false;
      }
    }
  }

  Future<void> logoutMobileSession({
    required MobileAuthApi authApi,
  }) async {
    final operationId = _startAuthOperation();
    final currentRefreshToken = (_mobileRefreshToken ?? '').trim();

    _isLoading = true;
    _isAdmin = false;
    _error = null;
    _rememberMe = false;
    clearMobileSession(notify: false);
    notifyListeners();

    try {
      if (currentRefreshToken.isNotEmpty) {
        await authApi.logoutMobileSession(refreshToken: currentRefreshToken);
      }
    } catch (_) {
      // Best effort logout: local session is always cleared.
    }

    if (!_isCurrentAuthOperation(operationId)) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    if (!_isCurrentAuthOperation(operationId)) {
      return;
    }

    await _clearPersistedMobileSession(
      prefs: prefs,
      clearRememberPreference: true,
    );

    if (!_isCurrentAuthOperation(operationId)) {
      return;
    }

    _isLoading = false;
    notifyListeners();
  }

  void setMobileSession({
    required String accessToken,
    required String refreshToken,
    required String role,
    String? username,
    String? displayName,
  }) {
    _isAdmin = false;

    final normalizedAccessToken = accessToken.trim();
    _mobileAccessToken =
        normalizedAccessToken.isEmpty ? null : normalizedAccessToken;

    final normalizedRefreshToken = refreshToken.trim();
    _mobileRefreshToken =
        normalizedRefreshToken.isEmpty ? null : normalizedRefreshToken;

    final normalizedRole = role.trim().toLowerCase();
    _mobileRole = normalizedRole.isEmpty ? null : normalizedRole;

    final normalizedUsername = username?.trim() ?? '';
    _mobileUsername = normalizedUsername.isEmpty ? null : normalizedUsername;

    final normalizedDisplayName = displayName?.trim() ?? '';
    _mobileDisplayName =
      normalizedDisplayName.isEmpty ? null : normalizedDisplayName;
    notifyListeners();
  }

  void clearMobileSession({bool notify = true}) {
    _mobileAccessToken = null;
    _mobileRefreshToken = null;
    _mobileRole = null;
    _mobileUsername = null;
    _mobileDisplayName = null;
    if (notify) {
      notifyListeners();
    }
  }
  Future<void> _persistRememberedSession({
    required SharedPreferences prefs,
    required String accessToken,
    required String refreshToken,
    required String role,
    required String? username,
    required String? displayName,
    required bool rememberMe,
  }) async {
    await prefs.setBool(_prefRememberMe, rememberMe);
    await prefs.setString(_prefAccessToken, accessToken);
    await prefs.setString(_prefRefreshToken, refreshToken);
    await prefs.setString(_prefRole, role);
    if (username != null && username.trim().isNotEmpty) {
      await prefs.setString(_prefUsername, username.trim());
    } else {
      await prefs.remove(_prefUsername);
    }

    if (displayName != null && displayName.trim().isNotEmpty) {
      await prefs.setString(_prefDisplayName, displayName.trim());
    } else {
      await prefs.remove(_prefDisplayName);
    }
  }

  Future<void> _clearPersistedMobileSession({
    required SharedPreferences prefs,
    required bool clearRememberPreference,
  }) async {
    await prefs.remove(_prefAccessToken);
    await prefs.remove(_prefRefreshToken);
    await prefs.remove(_prefRole);
    await prefs.remove(_prefUsername);
    await prefs.remove(_prefDisplayName);

    if (clearRememberPreference) {
      await prefs.remove(_prefRememberMe);
    }
  }
}
