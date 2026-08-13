import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

enum CastStatus { idle, connecting, connected, unsupported, failed }

typedef CastFallbackLauncher = Future<bool> Function(Uri uri);

class CastService extends ChangeNotifier {
  CastService({
    MethodChannel? channel,
    CastFallbackLauncher? launchFallback,
  })  : _channel = channel ?? const MethodChannel('com.751152.duckmusic/cast'),
        _launchFallback = launchFallback ?? _defaultLaunchFallback {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  final MethodChannel _channel;
  final CastFallbackLauncher _launchFallback;
  CastStatus status = CastStatus.idle;
  String message = '';
  bool shouldPauseLocalPlayback = false;

  Future<bool> start({required String mediaUrl, required String title}) async {
    final uri = Uri.tryParse(mediaUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      message = '投屏地址无效';
      status = CastStatus.failed;
      notifyListeners();
      return false;
    }

    status = CastStatus.connecting;
    message = '正在打开投屏设备';
    notifyListeners();
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'startCast',
        {'url': mediaUrl, 'title': title},
      );
      if (result?['supported'] != true) {
        markUnsupported(
          result?['message']?.toString() ?? '当前设备暂不支持原生投屏',
        );
        return false;
      }
      if (result?['connected'] == true) {
        _setConnected(
          result?['message']?.toString(),
          pauseLocal: result?['pauseLocal'] == true,
        );
      } else {
        status = CastStatus.idle;
        shouldPauseLocalPlayback = false;
        message = result?['message']?.toString() ?? '请选择投屏设备';
        notifyListeners();
      }
      return true;
    } on MissingPluginException {
      markUnsupported('当前设备暂不支持原生投屏');
      return false;
    } on PlatformException catch (error) {
      status = error.code == 'unsupported'
          ? CastStatus.unsupported
          : CastStatus.failed;
      message = error.message ?? '投屏连接失败';
      notifyListeners();
      return false;
    } catch (_) {
      status = CastStatus.failed;
      message = '投屏服务响应异常';
      notifyListeners();
      return false;
    }
  }

  Future<bool> showDevicePicker() async {
    status = CastStatus.connecting;
    message = '正在打开投屏设备';
    notifyListeners();
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'showRoutePicker',
        const {'audioOnly': true},
      );
      if (result?['supported'] != true) {
        markUnsupported(
          result?['message']?.toString() ?? '当前设备暂不支持原生投屏',
        );
        return false;
      }
      if (result?['connected'] == true) {
        _setConnected(
          result?['message']?.toString(),
          pauseLocal: result?['pauseLocal'] == true,
        );
      } else {
        status = CastStatus.idle;
        shouldPauseLocalPlayback = false;
        message = result?['message']?.toString() ?? '请选择投屏设备';
        notifyListeners();
      }
      return true;
    } on MissingPluginException {
      markUnsupported('当前设备暂不支持原生投屏');
      return false;
    } on PlatformException catch (error) {
      status = error.code == 'unsupported'
          ? CastStatus.unsupported
          : CastStatus.failed;
      message = error.message ?? '投屏连接失败';
      notifyListeners();
      return false;
    } catch (_) {
      status = CastStatus.failed;
      message = '投屏服务响应异常';
      notifyListeners();
      return false;
    }
  }

  Future<bool> openFallback(String playbackPage) async {
    final uri = Uri.tryParse(playbackPage);
    if (!_isAllowedFallback(uri)) return false;
    return _launchFallback(uri!);
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stopCast');
    } on MissingPluginException {
      // Native casting is optional on unsupported platforms.
    } on PlatformException {
      // Reset local state even if the native route has already disappeared.
    }
    status = CastStatus.idle;
    shouldPauseLocalPlayback = false;
    message = '';
    notifyListeners();
  }

  void markUnsupported(String text) {
    status = CastStatus.unsupported;
    shouldPauseLocalPlayback = false;
    message = text;
    notifyListeners();
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method != 'castStateChanged') return null;
    final raw = call.arguments;
    final args = raw is Map ? Map<Object?, Object?>.from(raw) : const {};
    if (args['connected'] == true) {
      _setConnected(
        args['message']?.toString(),
        pauseLocal: args['pauseLocal'] == true,
      );
    } else {
      status = CastStatus.idle;
      shouldPauseLocalPlayback = false;
      message = args['message']?.toString() ?? '投屏已断开';
      notifyListeners();
    }
    return null;
  }

  void _setConnected(String? nativeMessage, {bool pauseLocal = false}) {
    status = CastStatus.connected;
    shouldPauseLocalPlayback = pauseLocal;
    message = nativeMessage ?? '已连接投屏设备';
    notifyListeners();
  }

  static bool _isAllowedFallback(Uri? uri) {
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return false;
    final host = uri.host.toLowerCase();
    return host == 'ncat21.com' || host.endsWith('.ncat21.com');
  }

  static Future<bool> _defaultLaunchFallback(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
