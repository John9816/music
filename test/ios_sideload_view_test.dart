import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:duck_music/core/models/ios_sideload.dart';
import 'package:duck_music/core/services/ios_sideload_service.dart';
import 'package:duck_music/features/settings/ios_sideload_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

const manifestUrl = 'https://ecs.example.com/ios/latest.json';
const ipaUrl = 'https://ecs.example.com/ios/DuckMusic.ipa';
final bytes = utf8.encode('widget ipa');
final hash = sha256.convert(bytes).toString();

class WidgetAdapter implements IosSideloadPlatformAdapter {
  WidgetAdapter(this.statusResult);

  final IosSideloadStatus statusResult;

  @override
  Future<IosSideloadStatus> status() async => statusResult;

  @override
  Future<IosSideloadStatus> install(
    IosSideloadManifest manifest,
    String ipaPath,
  ) async =>
      statusResult;

  @override
  Future<IosSideloadStatus> refresh(
    IosSideloadManifest manifest,
    String ipaPath,
  ) async =>
      statusResult;

  @override
  Future<void> cancel() async {}
}

Widget buildHarness(IosSideloadService service) {
  return ChangeNotifierProvider.value(
    value: service,
    child: MaterialApp(
      theme: ThemeData.light(),
      home: const IosSideloadView(),
    ),
  );
}

void main() {
  testWidgets('shows actionable diagnostics when ECS is not configured',
      (tester) async {
    final service = IosSideloadService(
      client: MockClient((_) async => http.Response('', 500)),
      adapter: WidgetAdapter(const IosSideloadStatus()),
      manifestUrl: '',
    );
    addTearDown(service.dispose);

    await tester.pumpWidget(buildHarness(service));
    await tester.pumpAndSettle();

    expect(find.text('iOS 安装中心'), findsOneWidget);
    expect(find.textContaining('清单地址尚未配置'), findsOneWidget);
    expect(find.text('安装最新版本'), findsOneWidget);
  });

  testWidgets('renders the verified build and device status', (tester) async {
    final service = IosSideloadService(
      client: MockClient((request) async {
        if (request.url.toString() == manifestUrl) {
          return http.Response(
            jsonEncode({
              'version': '1.2.0',
              'buildNumber': 12,
              'downloadUrl': ipaUrl,
              'sha256': hash,
            }),
            200,
          );
        }
        return http.Response.bytes(bytes, 200);
      }),
      adapter: WidgetAdapter(
        const IosSideloadStatus(
          accountLabel: 'test@example.com',
          devices: [
            IosSideloadDevice(
              name: '测试 iPhone',
              identifier: 'device-1',
              connected: true,
              trusted: true,
              developerModeEnabled: true,
            ),
          ],
        ),
      ),
      manifestUrl: manifestUrl,
    );
    addTearDown(service.dispose);

    await tester.pumpWidget(buildHarness(service));
    await tester.pumpAndSettle();

    expect(find.text('1.2.0 (12)'), findsOneWidget);
    expect(find.textContaining('测试 iPhone'), findsOneWidget);
    expect(find.text('test@example.com'), findsOneWidget);
  });
}
