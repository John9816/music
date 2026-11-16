import 'dart:async';
import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../api/qishui_feed_api.dart';
import '../models/song.dart';

/// Owns server sequencing and protects every response with the account epoch.
class RoamingSession extends ChangeNotifier {
  RoamingSession({required this.api, required this.identity});
  final QishuiFeedApi api;
  final String? Function() identity;
  String? _owner;
  RoamingPage? _page;
  List<Song> _songs = [];
  final Set<String> _seen = {};
  int _generation = 0;
  bool _disposed = false, _loading = false;
  String? _error;
  Future<List<Song>>? _next;
  bool get active => _page != null && _owner == identity();
  bool get loading => _loading;
  String? get error => _error;
  String? get modeId => _page?.modeId;
  List<Song> get songs => List.unmodifiable(_songs);
  bool get hasMore => active && _page!.hasMore;
  bool _valid(int generation, String? owner) =>
      !_disposed &&
      generation == _generation &&
      owner != null &&
      owner == identity();
  Future<void> start({String? modeId}) async {
    final owner = identity();
    final closing = stop();
    final generation = _generation;
    await closing;
    if (!_valid(generation, owner)) return;
    _owner = owner;
    _loading = true;
    _error = null;
    _notify();
    try {
      final result = await api.start(modeId: modeId);
      if (!_valid(generation, owner)) return;
      if (result.sessionId.isEmpty || result.songs.isEmpty) {
        throw StateError('empty feed');
      }
      _page = result;
      _songs = _unique(result.songs);
    } catch (error) {
      if (_valid(generation, owner)) _error = _message(error);
    } finally {
      if (_valid(generation, owner)) {
        _loading = false;
        _notify();
      }
    }
  }

  Future<List<Song>> next() {
    if (!active || _disposed) return Future.value([]);
    if (_next != null) return _next!;
    late final Future<List<Song>> pending;
    pending = _loadNext().whenComplete(() {
      if (identical(_next, pending)) _next = null;
    });
    return _next = pending;
  }

  Future<List<Song>> _loadNext() async {
    final page = _page!;
    final generation = _generation;
    final owner = _owner;
    if (!page.hasMore) return [];
    if (page.expiresAt != null && page.expiresAt!.isBefore(DateTime.now())) {
      _error = '本次漫游已结束，请重新开始';
      _notify();
      return [];
    }
    _loading = true;
    _error = null;
    _notify();
    try {
      final result = await api.next(page.sessionId, page.nextSequence,
          modeId: page.modeId);
      if (!_valid(generation, owner)) return [];
      if (result.sessionId != page.sessionId ||
          result.nextSequence <= page.nextSequence) {
        throw StateError('invalid feed sequence');
      }
      _page = result;
      final added = _unique(result.songs);
      _songs = [..._songs, ...added];
      if (_songs.length > 200) _songs = _songs.sublist(_songs.length - 200);
      if (added.isEmpty) _error = '暂时没有新歌曲，稍后重试';
      return added;
    } catch (error) {
      if (_valid(generation, owner)) _error = _message(error);
      return [];
    } finally {
      if (_valid(generation, owner)) {
        _loading = false;
        _notify();
      }
    }
  }

  List<Song> _unique(List<Song> songs) {
    final result =
        songs.where((s) => _seen.add('${s.source}:${s.id}')).toList();
    if (_seen.length > 2000) {
      _seen.removeAll(_seen.take(_seen.length - 1000).toList());
    }
    return result;
  }

  Future<void> stop() async {
    final page = _page;
    final canClose = _owner != null && _owner == identity();
    _generation++;
    _page = null;
    _songs = [];
    _seen.clear();
    _next = null;
    _loading = false;
    _error = null;
    _owner = null;
    _notify();
    if (page != null && canClose) {
      try {
        await api.close(page.sessionId);
      } catch (_) {}
    }
  }

  String _message(Object error) {
    if (error is ApiException) {
      if (error.unauthorized) return '请登录后重新开始漫游';
      final lower = error.message.toLowerCase();
      // 后端用 409 表达三种完全不同的状态。把"会话失效"也说成"请重新扫码"，
      // 会让用户以为授权掉了 —— 实际只需要重开一次漫游。
      if (lower.contains('binding changed')) {
        return '漫游会话已失效，重新开始即可';
      }
      if (lower.contains('authorization expired') ||
          lower.contains('authorize again') ||
          lower.contains('identity is incomplete')) {
        return '授权已过期，请在黑源账号里刷新授权';
      }
      if (lower.contains('bind') || lower.contains('绑定')) {
        return '还没有绑定黑源账号，请先扫码绑定';
      }
      switch (error.statusCode) {
        case 404:
          return '本次漫游已结束，重新开始即可';
        case 409:
          return '漫游会话已失效，重新开始即可';
        case 429:
          return '操作太快了，稍等一下再试';
        case 503:
          return '服务正忙，稍后重试';
        case 504:
          return '上游响应超时，稍后重试';
      }
    }
    return '漫游暂时不可用，请重试';
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
