import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../player/lrc_parser.dart';
import '../player/player_controller.dart';
import '../settings/settings_controller.dart';

class DesktopShortcutSpec {
  const DesktopShortcutSpec(this.id, this.title, this.subtitle);

  final String id;
  final String title;
  final String subtitle;
}

const playbackShortcutSpecs = <DesktopShortcutSpec>[
  DesktopShortcutSpec('playPause', '播放 / 暂停', '控制当前音乐的播放状态'),
  DesktopShortcutSpec('previous', '上一首', '切换到实际上一首歌曲'),
  DesktopShortcutSpec('next', '下一首', '切换到下一首歌曲'),
  DesktopShortcutSpec('volumeUp', '增大音量', '播放器音量增加 5%'),
  DesktopShortcutSpec('volumeDown', '减小音量', '播放器音量降低 5%'),
  DesktopShortcutSpec('mute', '静音 / 恢复', '切换播放器静音状态'),
  DesktopShortcutSpec('favorite', '喜欢 / 取消喜欢', '更新当前歌曲喜欢状态'),
  DesktopShortcutSpec('loop', '切换循环模式', '不循环、列表循环和单曲循环'),
  DesktopShortcutSpec('shuffle', '随机播放', '开启或关闭随机播放'),
];

const windowShortcutSpecs = <DesktopShortcutSpec>[
  DesktopShortcutSpec('window', '显示 / 隐藏主窗口', '切换主窗口可见状态'),
  DesktopShortcutSpec('search', '打开搜索', '显示主窗口并打开搜索'),
  DesktopShortcutSpec('lyrics', '显示 / 隐藏歌词', '切换状态栏歌词'),
];

/// macOS / Windows / Linux 的全局快捷键与 macOS 状态栏歌词桥接。
class DesktopIntegrationService extends ChangeNotifier {
  DesktopIntegrationService({
    required this.settings,
    required this.player,
    this.onOpenSearch,
  });

  static const _windowChannel = MethodChannel('duckmusic/window');

  final SettingsController settings;
  final PlayerController player;
  final VoidCallback? onOpenSearch;

  final Map<String, HotKey> _registered = {};
  final Map<String, String> _errors = {};
  StreamSubscription<Duration>? _positionSubscription;
  List<LrcLine> _lyrics = const [];
  String _lastLyricSource = '';
  String _lastStatusText = '';
  String _settingsFingerprint = '';
  bool _disposed = false;

  bool get supported =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  String? errorFor(String action) => _errors[action];

  Future<void> initialize() async {
    if (!supported) return;
    settings.addListener(_settingsChanged);
    player.addListener(_playerChanged);
    _positionSubscription = player.positionStream.listen(_updateStatusLyric);
    try {
      await hotKeyManager.unregisterAll();
    } catch (_) {}
    await _refreshShortcuts(force: true);
    await _syncStatusLyrics();
  }

  void _settingsChanged() {
    unawaited(_refreshShortcuts());
    unawaited(_syncStatusLyrics());
  }

  void _playerChanged() {
    if (_lastLyricSource == player.lyric) return;
    _lastLyricSource = player.lyric;
    _lyrics = parseLrc(player.lyric);
    _updateStatusLyric(player.position);
  }

  Future<void> _refreshShortcuts({bool force = false}) async {
    if (!supported || _disposed) return;
    final fingerprint = jsonEncode({
      'enabled': settings.globalShortcutsEnabled,
      'bindings': settings.shortcutBindings,
    });
    if (!force && fingerprint == _settingsFingerprint) return;
    _settingsFingerprint = fingerprint;

    for (final hotKey in _registered.values) {
      try {
        await hotKeyManager.unregister(hotKey);
      } catch (_) {}
    }
    _registered.clear();
    _errors.clear();
    if (!settings.globalShortcutsEnabled) {
      notifyListeners();
      return;
    }

    for (final entry in settings.shortcutBindings.entries) {
      try {
        final decoded = jsonDecode(entry.value);
        if (decoded is! Map) continue;
        final hotKey = HotKey.fromJson(Map<String, dynamic>.from(decoded));
        await hotKeyManager.register(
          hotKey,
          keyDownHandler: (_) => _run(entry.key),
        );
        _registered[entry.key] = hotKey;
      } catch (error) {
        _errors[entry.key] = _friendlyRegistrationError(error);
      }
    }
    notifyListeners();
  }

  void _run(String action) {
    switch (action) {
      case 'playPause':
        unawaited(player.togglePlay());
        return;
      case 'previous':
        unawaited(player.previous());
        return;
      case 'next':
        unawaited(player.next());
        return;
      case 'volumeUp':
        unawaited(player.setVolume((player.volume + 0.05).clamp(0, 1)));
        return;
      case 'volumeDown':
        unawaited(player.setVolume((player.volume - 0.05).clamp(0, 1)));
        return;
      case 'mute':
        unawaited(player.setVolume(player.volume <= 0 ? 0.7 : 0));
        return;
      case 'favorite':
        player.toggleLike();
        return;
      case 'loop':
        unawaited(player.cycleLoopMode());
        return;
      case 'shuffle':
        player.toggleShuffle();
        return;
      case 'window':
        unawaited(_windowChannel.invokeMethod<void>('toggleVisibility'));
        return;
      case 'search':
        unawaited(_windowChannel.invokeMethod<void>('showWindow'));
        onOpenSearch?.call();
        return;
      case 'lyrics':
        unawaited(settings.setStatusBarLyrics(!settings.statusBarLyrics));
        return;
    }
  }

  Future<void> _syncStatusLyrics() async {
    if (!Platform.isMacOS) return;
    try {
      await _windowChannel.invokeMethod<void>('setStatusLyrics', {
        'enabled': settings.statusBarLyrics,
        'text': settings.statusBarLyrics ? _lastStatusText : '',
      });
    } catch (_) {}
  }

  void _updateStatusLyric(Duration position) {
    if (!Platform.isMacOS || !settings.statusBarLyrics) return;
    var text = player.current?.name ?? '柒伍壹壹音乐';
    for (final line in _lyrics) {
      if (line.time > position) break;
      text = line.text;
    }
    if (text == _lastStatusText) return;
    _lastStatusText = text;
    unawaited(_syncStatusLyrics());
  }

  String _friendlyRegistrationError(Object error) {
    final text = error.toString();
    if (text.toLowerCase().contains('already')) return '该组合已被占用';
    return '注册失败，请换一个组合';
  }

  @override
  void dispose() {
    _disposed = true;
    settings.removeListener(_settingsChanged);
    player.removeListener(_playerChanged);
    _positionSubscription?.cancel();
    for (final hotKey in _registered.values) {
      unawaited(hotKeyManager.unregister(hotKey).catchError((_) {}));
    }
    super.dispose();
  }
}
