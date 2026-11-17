import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:duck_music/core/services/skin_asset_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test 默认 mock 所有 HttpClient（恒返回 400），这里解除以验证真实本地服务。
  HttpOverrides.global = null;

  test('本地资源服务能启动并通过 HTTP 提供皮肤入口与 ES module', () async {
    final server = SkinAssetServer.instance;
    final origin = await server.start();
    addTearDown(() => server.dispose());

    expect(origin, matches(r'^http://127\.0\.0\.1:\d+$'));

    final client = HttpClient();
    addTearDown(client.close);

    // Folia 入口 HTML
    final htmlReq = await client.getUrl(Uri.parse('$origin/folia/index.html'));
    final htmlRes = await htmlReq.close();
    expect(htmlRes.statusCode, 200);
    expect(htmlRes.headers.contentType?.mimeType, 'text/html');
    final html = await utf8.decoder.bind(htmlRes).join();
    expect(html, contains('type="module"'));
    expect(html, contains('host.js'));

    // host.js 必须是 application/javascript，且包含对方协议入口
    final jsReq = await client.getUrl(Uri.parse('$origin/folia/host.js'));
    final jsRes = await jsReq.close();
    expect(jsRes.statusCode, 200);
    expect(jsRes.headers.contentType?.mimeType, 'application/javascript');
    final js = await utf8.decoder.bind(jsRes).join();
    expect(js, contains('window.TfnNebbia'));
    expect(js, contains('receive(packet)'));

    // 动态 import 的分片可访问（ES module 加载的关键）
    final chunkReq =
        await client.getUrl(Uri.parse('$origin/folia/renderer.js'));
    final chunkRes = await chunkReq.close();
    expect(chunkRes.statusCode, 200);
    expect(chunkRes.headers.contentType?.mimeType, 'application/javascript');
    await chunkRes.drain();

    // Nebbia 入口同样可访问
    final nebReq = await client.getUrl(Uri.parse('$origin/nebbia/index.html'));
    final nebRes = await nebReq.close();
    expect(nebRes.statusCode, 200);
    await nebRes.drain();
  });

  test('路径穿越被拒绝', () async {
    final server = SkinAssetServer.instance;
    final origin = await server.start();
    final client = HttpClient();
    addTearDown(client.close);
    final req =
        await client.getUrl(Uri.parse('$origin/../../etc/passwd'));
    final res = await req.close();
    expect(res.statusCode, 404);
    await res.drain();
  });
}
