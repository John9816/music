import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/api/api_client.dart';
import '../../core/api/qishui_api.dart';
import '../../core/auth/auth_controller.dart';

/// QR data lives only while this screen is open, scoped to the website session.
class QishuiAccountController extends ChangeNotifier {
  QishuiAccountController({required this.auth, QishuiApi? api})
      : _api = api ?? QishuiApi(),
        _session = auth.sessionGeneration {
    auth.addListener(_sessionChanged);
  }
  final AuthController auth;
  final QishuiApi _api;
  int _session, _revision = 0;
  bool _disposed = false, _active = true, _polling = false, busy = false;
  Timer? _timer;
  QishuiAccountInfo? account, qr;
  String? error;
  int _failures = 0;
  bool _current(int revision) =>
      !_disposed &&
      revision == _revision &&
      auth.sessionGeneration == _session &&
      auth.isLoggedIn;

  void _sessionChanged() {
    if (_session == auth.sessionGeneration) return;
    _session = auth.sessionGeneration;
    _revision++;
    _timer?.cancel();
    account = null;
    qr = null;
    error = null;
    busy = false;
    notifyListeners();
    if (auth.isLoggedIn) unawaited(load());
  }

  void setActive(bool active) {
    _active = active;
    _timer?.cancel();
    if (active) _schedule();
  }

  void cancelQr() {
    _revision++;
    _timer?.cancel();
    qr = null;
    busy = false;
    error = null;
    notifyListeners();
  }

  Future<void> load() => _action(_api.account, isQr: false);
  Future<void> refresh() => _action(_api.refresh, isQr: false);
  Future<void> start() => _action(_api.start, isQr: true);
  Future<void> unbind() => _action(() async {
        await _api.unbind();
        return QishuiAccountInfo.fromJson({'status': 'unbound'});
      }, isQr: false);

  Future<void> _action(Future<QishuiAccountInfo> Function() call,
      {required bool isQr}) async {
    if (busy || _disposed || !auth.isLoggedIn) return;
    final revision = ++_revision;
    _timer?.cancel();
    qr = null;
    error = null;
    busy = true;
    _failures = 0;
    notifyListeners();
    try {
      final result = await call();
      if (!_current(revision)) return;
      if (isQr) {
        if (result.sessionId == null ||
            result.sessionExpiresAt == null ||
            result.qrBytes == null) {
          throw ApiException('二维码无效，请重新获取');
        }
        qr = result;
      } else {
        account = result;
      }
    } catch (e) {
      if (_current(revision)) error = e.toString();
    } finally {
      if (_current(revision)) {
        busy = false;
        notifyListeners();
        _schedule();
      }
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (_disposed ||
        !_active ||
        _polling ||
        busy ||
        qr?.pending != true ||
        !auth.isLoggedIn) {
      return;
    }
    _timer = Timer(Duration(seconds: qr!.pollSeconds), _poll);
  }

  Future<void> _poll() async {
    final current = qr;
    if (_disposed ||
        !_active ||
        current == null ||
        !current.pending ||
        busy ||
        _polling) {
      return;
    }
    if (!DateTime.now().isBefore(current.sessionExpiresAt!)) {
      qr = null;
      error = '二维码已过期，请重新扫码';
      notifyListeners();
      return;
    }
    final revision = _revision;
    _polling = true;
    try {
      final result = await _api.poll(current.sessionId!);
      if (!_current(revision) || qr != current) return;
      _failures = 0;
      if (result.status == 'confirmed' && result.bound) {
        account = result;
        qr = null;
        error = null;
      } else if (!result.pending) {
        qr = null;
        error = switch (result.status) {
          'refused' => '已取消授权，可重新扫码',
          'expired' => '二维码已过期，请重新扫码',
          _ => '授权未完成，请重新扫码',
        };
      } else {
        // Poll replies do not repeat the PNG; retain this session's image.
        qr = QishuiAccountInfo.fromJson({
          'status': result.status,
          'sessionId': current.sessionId,
          'qrcode': current.qrcode,
          'qrcodeUrl': current.qrcodeUrl,
          'sessionExpiresAt': current.sessionExpiresAt!.toIso8601String(),
          'pollIntervalSeconds': result.pollSeconds
        });
        error = null;
      }
    } catch (e) {
      if (!_current(revision) || qr != current) return;
      error = e.toString();
      if (++_failures >= 3 ||
          e is ApiException && [401, 404, 409].contains(e.statusCode)) {
        qr = null;
      }
    } finally {
      _polling = false;
      if (!_disposed) {
        notifyListeners();
        _schedule();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    _timer?.cancel();
    auth.removeListener(_sessionChanged);
    super.dispose();
  }
}
