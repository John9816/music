import 'dart:async';
import 'package:flutter/foundation.dart';
import '../api/qishui_feed_api.dart';
import '../auth/auth_controller.dart';
import 'player_controller.dart';
import 'roaming_session.dart';

/// Connects a feed to the existing player; ordinary queue replacement exits it.
class RoamingController extends ChangeNotifier {
  RoamingController(
      {required this.player, required this.auth, QishuiFeedApi? api})
      : api = api ?? QishuiFeedApi() {
    session = RoamingSession(
        api: this.api,
        identity: () =>
            auth.isLoggedIn ? auth.sessionGeneration.toString() : null);
    _authGeneration = auth.sessionGeneration;
    session.addListener(_notify);
    player.addListener(_onPlayer);
    auth.addListener(_onAuth);
  }
  final PlayerController player;
  final AuthController auth;
  final QishuiFeedApi api;
  late final RoamingSession session;
  late int _authGeneration;
  int? _queueGeneration;
  int _operation = 0;
  bool _disposed = false, _starting = false;
  List<RoamingMode> _modes = [];
  List<RoamingMode> get modes => List.unmodifiable(_modes);
  bool get active => _queueGeneration != null && session.active;
  bool get loading => _starting || session.loading;
  String? get error => session.error;
  String get modeName =>
      _modes.where((m) => m.id == session.modeId).firstOrNull?.name ?? '为你推荐';
  Future<void> loadModes() async {
    final generation = auth.sessionGeneration;
    final result = await api.modes();
    if (_disposed || generation != auth.sessionGeneration) return;
    _modes = result;
    _notify();
  }

  Future<bool> start({String? modeId}) async {
    if (_starting || !auth.isLoggedIn) return false;
    _starting = true;
    _queueGeneration = null;
    player.loadMoreQueue = null;
    _notify();
    final generation = auth.sessionGeneration;
    final operation = ++_operation;
    final originalQueue = player.queueGeneration;
    bool current() =>
        !_disposed &&
        operation == _operation &&
        generation == auth.sessionGeneration &&
        originalQueue == player.queueGeneration;
    try {
      await session.start(modeId: modeId);
      if (!current()) {
        if (operation == _operation) await stop();
        return false;
      }
      if (!session.active) return false;
      await player.setPlaybackMode(PlaybackMode.listLoop);
      if (!current()) {
        if (operation == _operation) await stop();
        return false;
      }
      _queueGeneration = player.queueGeneration + 1;
      final playing = player.playQueue(session.songs);
      player.loadMoreQueue = loadMore;
      await playing;
      if (_queueGeneration != player.queueGeneration) {
        await stop();
        return false;
      }
      return active;
    } finally {
      _starting = false;
      _notify();
    }
  }

  Future<bool> loadMore() async {
    final queue = _queueGeneration;
    if (queue == null || queue != player.queueGeneration) return false;
    final songs = await session.next();
    if (_disposed ||
        queue != _queueGeneration ||
        queue != player.queueGeneration) {
      return false;
    }
    player.appendQueue(songs, generation: queue);
    return songs.isNotEmpty;
  }

  Future<void> stop() async {
    _operation++;
    _queueGeneration = null;
    player.loadMoreQueue = null;
    await session.stop();
    _notify();
  }

  void _onPlayer() {
    final generation = _queueGeneration;
    if (generation == null || _starting) return;
    if (generation != player.queueGeneration) {
      unawaited(stop());
      return;
    }
    if (session.hasMore &&
        !session.loading &&
        session.error == null &&
        player.queue.length - player.queueIndex <= 4) {
      unawaited(loadMore());
    }
  }

  void _onAuth() {
    if (_authGeneration == auth.sessionGeneration) return;
    _authGeneration = auth.sessionGeneration;
    _modes = [];
    unawaited(stop());
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    auth.removeListener(_onAuth);
    player.removeListener(_onPlayer);
    session.removeListener(_notify);
    player.loadMoreQueue = null;
    unawaited(session.stop());
    session.dispose();
    super.dispose();
  }
}
