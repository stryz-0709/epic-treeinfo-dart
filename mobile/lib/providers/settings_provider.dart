import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/app_localizations.dart';

class SettingsProvider extends ChangeNotifier {
  // ── Theme ─────────────────────────────────────────────
  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  // ── Locale ────────────────────────────────────────────
  String _locale = 'vi';
  String get locale => _locale;

  AppLocalizations get l => AppLocalizations(_locale);

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _locale = prefs.getString('locale') ?? 'vi';
    final themeStr = prefs.getString('themeMode') ?? 'system';
    switch (themeStr) {
      case 'light':
        _themeMode = ThemeMode.light;
      case 'dark':
        _themeMode = ThemeMode.dark;
      default:
        _themeMode = ThemeMode.system;
    }
    notifyListeners();
  }

  Future<void> setLocale(String locale) async {
    _locale = locale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale', locale);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    String modeStr;
    switch (mode) {
      case ThemeMode.light:
        modeStr = 'light';
      case ThemeMode.dark:
        modeStr = 'dark';
      default:
        modeStr = 'system';
    }
    await prefs.setString('themeMode', modeStr);
  }
}
