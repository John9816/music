import 'dart:async';

import '../api/music_social_api.dart';
import '../auth/auth_controller.dart';
import '../player/player_controller.dart';

/// 听歌时长心跳上报。
///
/// 只统计「真正在播放」的墙钟秒数：监听 [PlayerController.playingStream]，
/// 播放时每秒累加；每满一个心跳周期（默认 30 秒）上报一次真实播放秒数。
/// 暂停时停止累计但不丢弃不足一个周期的余数；切歌不重置（后端按 user+day 聚合）。
/// 登录态变化 / 应用切后台时结算，避免串号或进程被杀导致丢数据。
class ListenTimeReporter {
  ListenTimeReporter({
    required PlayerController player,
    required AuthController auth,
    MusicSocialApi? api,
    this.interval = const Duration(seconds: 30),
  })  : _player = player,
        _auth = auth,
        _api = api ?? MusicSocialApi() {
    _playingSub = _player.playingStream.distinct().listen(_onPlayingChanged);
  }

  final PlayerController _player;
  final AuthController _auth;
  final MusicSocialApi _api;
  final Duration interval;

  StreamSubscription<bool>? _playingSub;
  Timer? _tick;
  int _pendingSeconds = 0;
  bool _reporting = false;

  void _onPlayingChanged(bool playing) {
    if (playing) {
      _startTicking();
    } else {
      _stopTicking();
    }
  }

  void _startTicking() {
    if (_tick != null) return;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      _pendingSeconds++;
      if (_pendingSeconds >= interval.inSeconds) unawaited(flush());
    });
  }

  void _stopTicking() {
    _tick?.cancel();
    _tick = null;
  }

  /// 立即上报当前累计的秒数（若已登录且有余数）。
  /// 上报失败时保留余数，下次再试；上报期间的新增秒数不会丢失。
  Future<void> flush() async {
    if (_reporting) return;
    final seconds = _pendingSeconds;
    if (seconds <= 0) return;
    final token = _auth.token;
    if (token == null) {
      // 未登录：丢弃未上报的秒数，避免登录后被算到新账号头上。
      _pendingSeconds = 0;
      return;
    }
    _pendingSeconds -= seconds;
    _reporting = true;
    try {
      await _api.reportHeartbeat(seconds, token);
    } catch (_) {
      // 上报失败：把秒数放回，等待下一次心跳或前台结算重试。
      _pendingSeconds += seconds;
    } finally {
      _reporting = false;
    }
  }

  /// 登录态变化（登出/切换账号）时调用：先结算旧会话，再清空余数。
  void onSessionChanged() {
    unawaited(flush());
    _pendingSeconds = 0;
  }

  void dispose() {
    unawaited(flush());
    _stopTicking();
    _playingSub?.cancel();
    _playingSub = null;
  }
}
