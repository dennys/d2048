import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings_keys.dart';

/// 使用者設定。唯一寫 prefs 的地方（比照 dHealth 的 SettingsModel）。
///
/// 建立方式一律用 [SettingsModel.load]，不要直接 new ——
/// 載入完成才交回控制权，首幀就是正確的值。
class SettingsModel extends ChangeNotifier {
  final SharedPreferences _prefs;

  SettingsModel._(this._prefs);

  static Future<SettingsModel> load() async {
    final prefs = await SharedPreferences.getInstance();
    final model = SettingsModel._(prefs);
    await model._loadPreferences();
    return model;
  }

  String _language = PrefsDefaults.language;
  String _theme = PrefsDefaults.theme;
  int _boardSize = PrefsDefaults.boardSize;
  bool _haptics = PrefsDefaults.haptics;

  String get language => _language;
  String get theme => _theme;
  int get boardSize => _boardSize;
  bool get haptics => _haptics;

  Future<void> _loadPreferences() async {
    _language = _prefs.getString(Prefs.language) ?? PrefsDefaults.language;
    _theme = _prefs.getString(Prefs.theme) ?? PrefsDefaults.theme;
    _boardSize = _clampSize(_prefs.getInt(Prefs.boardSize));
    _haptics = _prefs.getBool(Prefs.haptics) ?? PrefsDefaults.haptics;
  }

  int _clampSize(int? value) {
    if (value != null && PrefsDefaults.boardSizeOptions.contains(value)) return value;
    return PrefsDefaults.boardSize;
  }

  Future<void> setLanguage(String language) async {
    _language = language;
    await _prefs.setString(Prefs.language, language);
    notifyListeners();
  }

  Future<void> setTheme(String theme) async {
    _theme = theme;
    await _prefs.setString(Prefs.theme, theme);
    notifyListeners();
  }

  Future<void> setBoardSize(int size) async {
    _boardSize = _clampSize(size);
    await _prefs.setInt(Prefs.boardSize, _boardSize);
    notifyListeners();
  }

  Future<void> setHaptics(bool haptics) async {
    _haptics = haptics;
    await _prefs.setBool(Prefs.haptics, haptics);
    notifyListeners();
  }

  Locale? getLocale() {
    switch (_language) {
      case 'en':
        return const Locale('en', '');
      case 'zh_Hant':
        return const Locale('zh', 'Hant');
      case 'zh_Hans':
        return const Locale('zh', 'Hans');
      case 'system':
      default:
        return null;
    }
  }

  ThemeMode getThemeMode() {
    switch (_theme) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }
}