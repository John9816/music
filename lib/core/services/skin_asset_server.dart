import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// 为播放页皮肤 WebView 提供本地 HTTP 静态资源。
///
/// 为什么不用 `loadFlutterAsset` 的 `file:///android_asset/`：
/// TuneFreeNext 的 Folia/Nebbia 皮肤是 ES module 工程，`host.js` 里用
/// `import './chunk-xxx.js'` 动态加载分片，并依赖 `document.baseURI`。
/// WebView 在 `file://` 下会因 CORS 拦截模块加载。对方自己也是通过
/// `WebViewResourceBridge` + localHostname 提供资源的，这里用 dart:io 的
/// 本地 HttpServer 实现同样的效果：资源仍是 App 内置、零外网访问。
class SkinAssetServer {
  SkinAssetServer._();

  static final SkinAssetServer instance = SkinAssetServer._();

  HttpServer? _server;
  String? _root;
  int? _port;
  Future<void>? _starting;

  /// 资源在 flutter assets 中的前缀，对应 pubspec 里声明的目录。
  static const _assetRoot = 'assets/player/tfn';

  /// 本地服务地址的根，例如 `http://127.0.0.1:43210`。
  String? get origin => _port == null ? null : 'http://127.0.0.1:$_port';

  /// 确保服务已启动并把资源解包到临时目录，返回 base origin。
  Future<String> start() {
    final started = _starting;
    if (started != null) return started.then((_) => origin!);
    final Completer<void> completer = Completer<void>();
    _starting = completer.future;
    unawaited(_bootstrap(completer));
    return completer.future.then((_) => origin!);
  }

  Future<void> _bootstrap(Completer<void> completer) async {
    try {
      final root = await _unpackAssets();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _root = root;
      _server = server;
      _port = server.port;
      server.listen(_handle);
      completer.complete();
    } catch (error, stack) {
      _starting = null;
      completer.completeError(error, stack);
    }
  }

  /// 把 assets 里的皮肤资源解到临时目录一次，后续直接从磁盘提供。
  Future<String> _unpackAssets() async {
    final temp = Directory.systemTemp;
    final root = Directory('${temp.path}/duck_music_skin_assets');
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final keys = manifest
        .listAssets()
        .where((key) => key.startsWith('$_assetRoot/'))
        .toList();
    if (keys.isEmpty) {
      throw StateError('No skin assets found under $_assetRoot');
    }
    for (final key in keys) {
      final relative = key.substring('$_assetRoot/'.length);
      final file = File('${root.path}/$relative');
      await file.create(recursive: true);
      await file.writeAsBytes(await rootBundle.load(key).then((b) => b.buffer
          .asUint8List(b.offsetInBytes, b.lengthInBytes)));
    }
    return root.path;
  }

  void _handle(HttpRequest request) {
    try {
      final requested = Uri.decodeComponent(request.uri.path);
      // 归一化路径，杜绝 `..` 穿越到临时目录之外。
      final segments = requested.split('/')..removeWhere((s) => s.isEmpty || s == '.' || s == '..');
      final safePath = segments.join('/');
      final file = File('$_root/$safePath');
      if (safePath.isEmpty || !file.existsSync()) {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('Not found')
          ..close();
        return;
      }
      final bytes = file.readAsBytesSync();
      final parts = _mimeFor(safePath).split('/');
      final mime = ContentType(parts[0], parts[1],
          charset: _isText(safePath) ? 'utf-8' : null);
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = mime
        ..headers.set('cache-control', 'public, max-age=3600')
        ..add(bytes)
        ..close();
    } catch (_) {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..close();
    }
  }

  bool _isText(String path) =>
      path.endsWith('.js') ||
      path.endsWith('.html') ||
      path.endsWith('.json') ||
      path.endsWith('.css') ||
      path.endsWith('.txt');

  String _mimeFor(String path) {
    if (path.endsWith('.html')) return 'text/html';
    if (path.endsWith('.js') || path.endsWith('.mjs')) return 'application/javascript';
    if (path.endsWith('.json')) return 'application/json';
    if (path.endsWith('.gz')) return 'application/gzip';
    if (path.endsWith('.css')) return 'text/css';
    if (path.endsWith('.png')) return 'image/png';
    if (path.endsWith('.wasm')) return 'application/wasm';
    if (path.endsWith('.txt')) return 'text/plain';
    return 'application/octet-stream';
  }

  /// 皮肤 WebView 销毁时不必关闭服务（多个皮肤页复用），App 退出时系统回收。
  void dispose() {
    _server?.close(force: true);
    _server = null;
    _port = null;
    _root = null;
    _starting = null;
  }
}
