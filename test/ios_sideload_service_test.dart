import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:duck_music/core/models/ios_sideload.dart';
import 'package:duck_music/core/services/ios_sideload_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const manifestUrl = 'https://ecs.example.com/ios/latest.json';
const ipaUrl = 'https://ecs.example.com/ios/DuckMusic.ipa';
final ipaBytes = utf8.encode('ipa bytes for test');
final ipaHash = sha256.convert(ipaBytes).toString();

Map<String, dynamic> manifestJson() => {
      'version': '1.2.0',
      'buildNumber': 12,
      'downloadUrl': ipaUrl,
      'sha256': ipaHash,
      'publishedAt': '2026-08-07T01:02:03Z',
    };

class FakeIosSideloadAdapter implements IosSideloadPlatformAdapter {
  FakeIosSideloadAdapter({this.statusResult = const IosSideloadStatus()});

  IosSideloadStatus statusResult;
  int installCalls = 0;
  int refreshCalls = 0;
  bool waitForInstall = false;
  String? receivedIpaPath;
  List<int>? receivedIpaBytes;

  @override
  Future<IosSideloadStatus> status() async => statusResult;

  @override
  Future<IosSideloadStatus> install(
    IosSideloadManifest manifest,
    String ipaPath,
  ) async {
    installCalls++;
    receivedIpaPath = ipaPath;
    receivedIpaBytes = await File(ipaPath).readAsBytes();
    if (waitForInstall) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return statusResult;
  }

  @override
  Future<IosSideloadStatus> refresh(
    IosSideloadManifest manifest,
    String ipaPath,
  ) async {
    refreshCalls++;
    receivedIpaPath = ipaPath;
    receivedIpaBytes = await File(ipaPath).readAsBytes();
    return statusResult;
  }

  @override
  Future<void> cancel() async {}
}

class MemoryIosSideloadStateStore implements IosSideloadStateStore {
  bool installed = false;
  String? version;

  @override
  Future<bool> hasInstalledBuild() async => installed;

  @override
  Future<void> saveInstalledBuild(String value) async {
    installed = true;
    version = value;
  }
}

void main() {
  test('persists only a local installed-build marker', () async {
    final directory = await Directory.systemTemp.createTemp('duckmusic-state-');
    addTearDown(() => directory.delete(recursive: true));
    final store = FileIosSideloadStateStore(
      path: '${directory.path}/ios-sideload.json',
    );

    expect(await store.hasInstalledBuild(), isFalse);
    await store.saveInstalledBuild('1.2.0');
    expect(await store.hasInstalledBuild(), isTrue);
    final contents = await File('${directory.path}/ios-sideload.json').readAsString();
    expect(contents, contains('"installed":true'));
    expect(contents, isNot(contains('password')));
    expect(contents, isNot(contains('mobileprovision')));
  });

  test('fetches and verifies the ECS manifest and IPA bytes', () async {
    final service = IosSideloadService(
      client: MockClient((request) async {
        if (request.url.toString() == manifestUrl) {
          return http.Response(jsonEncode(manifestJson()), 200);
        }
        expect(request.url.toString(), ipaUrl);
        return http.Response.bytes(ipaBytes, 200);
      }),
      adapter: FakeIosSideloadAdapter(),
      manifestUrl: manifestUrl,
    );

    final manifest = await service.loadManifest();
    expect(manifest.version, '1.2.0');
    await service.installLatest();
    expect(service.taskState, IosSideloadTaskState.success);
  });

  test('hands a verified temporary IPA to the local adapter and cleans it',
      () async {
    final adapter = FakeIosSideloadAdapter();
    final service = IosSideloadService(
      client: MockClient((request) async {
        if (request.url.toString() == manifestUrl) {
          return http.Response(jsonEncode(manifestJson()), 200);
        }
        return http.Response.bytes(ipaBytes, 200);
      }),
      adapter: adapter,
      manifestUrl: manifestUrl,
    );

    await service.loadManifest();
    await service.installLatest();

    expect(adapter.receivedIpaBytes, ipaBytes);
    expect(adapter.receivedIpaPath, isNotNull);
    expect(File(adapter.receivedIpaPath!).existsSync(), isFalse);
  });

  test('reports disabled configuration without making a request', () async {
    final service = IosSideloadService(
      client: MockClient((_) async => http.Response('', 500)),
      adapter: FakeIosSideloadAdapter(),
      manifestUrl: '',
    );

    expect(() => service.loadManifest(), throwsA(isA<IosSideloadException>()));
    expect(service.status.errorCode, IosSideloadErrorCode.notConfigured);
  });

  test('maps a missing local helper to a diagnostic status', () async {
    final adapter = ThrowingIosSideloadAdapter(
      const IosSideloadPlatformException(
        IosSideloadErrorCode.helperMissing,
        '未找到本地签名助手',
      ),
    );
    final service = IosSideloadService(
      client: MockClient((request) async {
        if (request.url.toString() == manifestUrl) {
          return http.Response(jsonEncode(manifestJson()), 200);
        }
        return http.Response.bytes(ipaBytes, 200);
      }),
      adapter: adapter,
      manifestUrl: manifestUrl,
    );

    await service.loadManifest();
    await service.installLatest();

    expect(service.taskState, IosSideloadTaskState.failed);
    expect(service.status.errorCode, IosSideloadErrorCode.helperMissing);
  });

  test('rejects a second install while the first task is running', () async {
    final adapter = FakeIosSideloadAdapter()..waitForInstall = true;
    final service = IosSideloadService(
      client: MockClient((request) async {
        if (request.url.toString() == manifestUrl) {
          return http.Response(jsonEncode(manifestJson()), 200);
        }
        return http.Response.bytes(ipaBytes, 200);
      }),
      adapter: adapter,
      manifestUrl: manifestUrl,
    );
    await service.loadManifest();

    final first = service.installLatest();
    await Future<void>.delayed(Duration.zero);
    expect(
      service.installLatest(),
      throwsA(
        isA<IosSideloadException>().having(
          (error) => error.code,
          'code',
          IosSideloadErrorCode.busy,
        ),
      ),
    );
    await first;
  });

  test('automatically refreshes an installed build within the 24-hour window',
      () async {
    final expiry = DateTime.utc(2026, 8, 7, 12);
    final adapter = FakeIosSideloadAdapter(
      statusResult: IosSideloadStatus(signatureExpiresAt: expiry),
    );
    final stateStore = MemoryIosSideloadStateStore()..installed = true;
    final service = IosSideloadService(
      client: MockClient((request) async {
        if (request.url.toString() == manifestUrl) {
          return http.Response(jsonEncode(manifestJson()), 200);
        }
        return http.Response.bytes(ipaBytes, 200);
      }),
      adapter: adapter,
      manifestUrl: manifestUrl,
      stateStore: stateStore,
      now: () => DateTime.utc(2026, 8, 7),
    );

    await service.autoRefreshIfNeeded();

    expect(adapter.refreshCalls, 1);
    expect(service.taskState, IosSideloadTaskState.success);
  });
}

class ThrowingIosSideloadAdapter implements IosSideloadPlatformAdapter {
  ThrowingIosSideloadAdapter(this.error);

  final IosSideloadPlatformException error;

  @override
  Future<IosSideloadStatus> status() async => throw error;

  @override
  Future<IosSideloadStatus> install(
    IosSideloadManifest manifest,
    String ipaPath,
  ) async =>
      throw error;

  @override
  Future<IosSideloadStatus> refresh(
    IosSideloadManifest manifest,
    String ipaPath,
  ) async =>
      throw error;

  @override
  Future<void> cancel() async {}
}
