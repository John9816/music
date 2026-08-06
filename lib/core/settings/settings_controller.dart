import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

/// 柒伍壹壹音乐的统一设置模型。
///
/// 所有会影响播放、外观、缓存和桌面行为的选项都在这里持久化，页面不再
/// 保存只在当前生命周期有效的临时状态。
class SettingsController extends ChangeNotifier {
  static const _sourceKey = 'music_source';
  static const _themeKey = 'theme';
  static const _themeModeKey = 'theme_mode';
  static const _accentKey = 'accent_color';
  static const _qualityKey = 'quality';
  static const _glassQualityKey = 'glass_quality';
  static const _reduceMotionKey = 'reduce_motion';
  static const _automaticAudioCacheKey = 'automatic_audio_cache';
  static const _audioCacheLimitKey = 'audio_cache_limit';
  static const _audioCacheValidityKey = 'audio_cache_validity';
  static const _downloadQualityKey = 'download_quality';
  static const _statusBarLyricsKey = 'status_bar_lyrics';
  static const _globalShortcutsKey = 'global_shortcuts_enabled';
  static const _shortcutBindingsKey = 'desktop_shortcut_bindings';

  String _source = 'netease';
  String _themeModeId = 'system';
  String _accentId = 'forestGreen';
  String _quality = 'auto';
  String _glassQuality = 'smooth';
  bool _reduceMotion = false;
  bool _automaticAudioCache = true;
  int _audioCacheLimitBytes = 0;
  int _audioCacheValidityDays = 30;
  String _downloadQuality = 'follow';
  bool _statusBarLyrics = false;
  bool _globalShortcutsEnabled = true;
  Map<String, String> _shortcutBindings = const {};
  bool _loaded = false;

  String get source => _source;
  String get themeModeId => _themeModeId;
  ThemeMode get themeMode => switch (_themeModeId) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
  String get accentId => _accentId;
  AppTheme get lightTheme => AppTheme.forAccent(_accentId, dark: false);
  AppTheme get darkTheme => AppTheme.forAccent(_accentId, dark: true);

  /// 兼容旧调用方；需要精确当前明暗时应使用 [lightTheme]/[darkTheme]。
  AppTheme get theme => _themeModeId == 'light' ? lightTheme : darkTheme;
  String get quality => _quality;
  String get glassQuality => _glassQuality;
  bool get reduceMotion => _reduceMotion;
  bool get automaticAudioCache => _automaticAudioCache;
  int get audioCacheLimitBytes => _audioCacheLimitBytes;
  int get audioCacheValidityDays => _audioCacheValidityDays;
  String get downloadQuality => _downloadQuality;
  bool get statusBarLyrics => _statusBarLyrics;
  bool get globalShortcutsEnabled => _globalShortcutsEnabled;
  Map<String, String> get shortcutBindings =>
      Map.unmodifiable(_shortcutBindings);
  bool get loaded => _loaded;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _source = prefs.getString(_sourceKey) ?? 'netease';
      _quality = prefs.getString(_qualityKey) ?? 'auto';
      _themeModeId = prefs.getString(_themeModeKey) ?? 'system';
      _accentId = prefs.getString(_accentKey) ?? 'forestGreen';
      _glassQuality = prefs.getString(_glassQualityKey) ?? 'smooth';
      _reduceMotion = prefs.getBool(_reduceMotionKey) ?? false;
      _automaticAudioCache = prefs.getBool(_automaticAudioCacheKey) ?? true;
      _audioCacheLimitBytes = prefs.getInt(_audioCacheLimitKey) ?? 0;
      _audioCacheValidityDays = prefs.getInt(_audioCacheValidityKey) ?? 30;
      _downloadQuality = prefs.getString(_downloadQualityKey) ?? 'follow';
      _statusBarLyrics = prefs.getBool(_statusBarLyricsKey) ?? false;
      _globalShortcutsEnabled = prefs.getBool(_globalShortcutsKey) ?? true;
      _shortcutBindings = _decodeBindings(
        prefs.getString(_shortcutBindingsKey),
      );
      _migrateLegacyTheme(prefs.getString(_themeKey));
    } catch (_) {
      // 使用默认值启动，避免损坏的偏好设置阻塞应用。
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> setSource(String value) =>
      _setString(_sourceKey, value, () => _source, (v) => _source = v);

  /// 兼容旧主题 id，同时保留现有调用方。
  Future<void> setTheme(String id) async {
    if (id == 'light' || id == 'dark') {
      await setThemeMode(id);
      return;
    }
    const legacyAccents = {
      'sunset': 'sunsetOrange',
      'ocean': 'skyBlue',
      'graphite': 'forestGreen',
    };
    await setAccentColor(legacyAccents[id] ?? id);
  }

  Future<void> setThemeMode(String value) => _setString(
        _themeModeKey,
        value,
        () => _themeModeId,
        (v) => _themeModeId = v,
      );

  Future<void> setAccentColor(String value) => _setString(
        _accentKey,
        value,
        () => _accentId,
        (v) => _accentId = v,
      );

  Future<void> setQuality(String value) =>
      _setString(_qualityKey, value, () => _quality, (v) => _quality = v);

  Future<void> setGlassQuality(String value) => _setString(
        _glassQualityKey,
        value,
        () => _glassQuality,
        (v) => _glassQuality = v,
      );

  Future<void> setReduceMotion(bool value) => _setBool(
        _reduceMotionKey,
        value,
        () => _reduceMotion,
        (v) => _reduceMotion = v,
      );

  Future<void> setAutomaticAudioCache(bool value) => _setBool(
        _automaticAudioCacheKey,
        value,
        () => _automaticAudioCache,
        (v) => _automaticAudioCache = v,
      );

  Future<void> setAudioCacheLimitBytes(int value) => _setInt(
        _audioCacheLimitKey,
        value,
        () => _audioCacheLimitBytes,
        (v) => _audioCacheLimitBytes = v,
      );

  Future<void> setAudioCacheValidityDays(int value) => _setInt(
        _audioCacheValidityKey,
        value,
        () => _audioCacheValidityDays,
        (v) => _audioCacheValidityDays = v,
      );

  Future<void> setDownloadQuality(String value) => _setString(
        _downloadQualityKey,
        value,
        () => _downloadQuality,
        (v) => _downloadQuality = v,
      );

  Future<void> setStatusBarLyrics(bool value) => _setBool(
        _statusBarLyricsKey,
        value,
        () => _statusBarLyrics,
        (v) => _statusBarLyrics = v,
      );

  Future<void> setGlobalShortcutsEnabled(bool value) => _setBool(
        _globalShortcutsKey,
        value,
        () => _globalShortcutsEnabled,
        (v) => _globalShortcutsEnabled = v,
      );

  Future<void> setShortcutBinding(String action, String? json) async {
    final next = Map<String, String>.from(_shortcutBindings);
    if (json == null) {
      next.remove(action);
    } else {
      next[action] = json;
    }
    _shortcutBindings = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_shortcutBindingsKey, jsonEncode(next));
  }

  Future<void> _setString(
    String key,
    String value,
    String Function() read,
    void Function(String) write,
  ) async {
    if (read() == value) return;
    write(value);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<void> _setBool(
    String key,
    bool value,
    bool Function() read,
    void Function(bool) write,
  ) async {
    if (read() == value) return;
    write(value);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _setInt(
    String key,
    int value,
    int Function() read,
    void Function(int) write,
  ) async {
    if (read() == value) return;
    write(value);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
  }

  void _migrateLegacyTheme(String? legacy) {
    if (legacy == null) return;
    if (legacy == 'light') _themeModeId = 'light';
    if (legacy == 'dark') _themeModeId = 'dark';
    if (legacy == 'sunset') _accentId = 'sunsetOrange';
    if (legacy == 'ocean') _accentId = 'skyBlue';
    if (legacy == 'graphite') _accentId = 'forestGreen';
  }

  Map<String, String> _decodeBindings(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    } catch (_) {
      return const {};
    }
  }
}
