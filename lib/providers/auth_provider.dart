import 'package:flutter/material.dart';

/// Simple admin-only auth provider (mirrors the Java hardcoded admin login).
class AuthProvider extends ChangeNotifier {
  bool _isAdmin = false;
  bool _isLoading = false;
  String? _error;

  bool get isAdmin => _isAdmin;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Attempt admin login with hardcoded credentials.
  bool login(String username, String password) {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final success = username == 'epic' && password == 'password';

    if (!success) {
      _error = 'login_failed';
    } else {
      _isAdmin = true;
    }

    _isLoading = false;
    notifyListeners();
    return success;
  }

  void logout() {
    _isAdmin = false;
    _error = null;
    notifyListeners();
  }
}
