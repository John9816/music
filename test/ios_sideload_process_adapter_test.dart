import 'dart:convert';

import 'package:duck_music/core/models/ios_sideload.dart';
import 'package:duck_music/core/services/ios_sideload_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeHelperRunner implements IosHelperCommandRunner {
  IosHelperCommandResult result = const IosHelperCommandResult(
    exitCode: 0,
    stdout: '{"ok":true}',
    stderr: '',
  );
  String? executable;
  List<String>? arguments;
  int cancelCalls = 0;

  @override
  Future<IosHelperCommandResult> run(
    String executable,
    List<String> arguments,
  ) async {
    this.executable = executable;
    this.arguments = arguments;
    return result;
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
  }
}

void main() {
  final manifest = IosSideloadManifest(
    version: '1.2.0',
    buildNumber: 12,
    downloadUrl: Uri(scheme: 'https', host: 'example.com', path: '/app.ipa'),
    sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  );

  test('discovers an explicitly configured helper before packaged fallbacks',
      () {
    final path = ProcessIosSideloadAdapter.resolveHelperPath(
      configuredPath: '/configured/helper',
      environment: const {'DUCKMUSIC_IOS_HELPER': '/environment/helper'},
      resolvedExecutable: '/Applications/7511.app/Contents/MacOS/7511',
      isMacOS: true,
      isWindows: false,
      fileExists: (candidate) => candidate == '/configured/helper',
    );

    expect(path, '/configured/helper');
  });

  test('parses helper status JSON without exposing credentials', () async {
    final runner = FakeHelperRunner()
      ..result = IosHelperCommandResult(
        exitCode: 0,
        stdout: jsonEncode({
          'ok': true,
          'accountLabel': 'test@example.com',
          'signatureExpiresAt': '2026-08-08T01:02:03Z',
          'devices': [
            {
              'name': '测试 iPhone',
              'identifier': 'device-1',
              'connected': true,
              'trusted': true,
              'developerModeEnabled': true,
            }
          ],
        }),
        stderr: '',
      );
    final adapter = ProcessIosSideloadAdapter(
      helperPath: '/tmp/duckmusic-ios-helper',
      helperExists: (_) => true,
      runner: runner,
    );

    final status = await adapter.status();

    expect(status.accountLabel, 'test@example.com');
    expect(status.devices.single.name, '测试 iPhone');
    expect(runner.arguments, ['status', '--json']);
  });

  test('maps structured helper failures', () async {
    final runner = FakeHelperRunner()
      ..result = const IosHelperCommandResult(
        exitCode: 2,
        stdout:
            '{"ok":false,"code":"appleDevicesMissing","message":"缺少 Apple Devices"}',
        stderr: '',
      );
    final adapter = ProcessIosSideloadAdapter(
      helperPath: '/tmp/duckmusic-ios-helper',
      helperExists: (_) => true,
      runner: runner,
    );

    expect(
      adapter.status(),
      throwsA(
        isA<IosSideloadPlatformException>().having(
          (error) => error.code,
          'code',
          IosSideloadErrorCode.appleDevicesMissing,
        ),
      ),
    );
  });

  test('passes only artifact metadata to install and supports cancellation',
      () async {
    final runner = FakeHelperRunner();
    final adapter = ProcessIosSideloadAdapter(
      helperPath: '/tmp/duckmusic-ios-helper',
      helperExists: (_) => true,
      runner: runner,
    );

    await adapter.install(manifest, '/tmp/DuckMusic.ipa');
    await adapter.cancel();

    expect(runner.arguments, [
      'install',
      '--json',
      '--ipa',
      '/tmp/DuckMusic.ipa',
      '--version',
      '1.2.0',
      '--build-number',
      '12',
      '--bundle-id',
      'com.751152.duckMusic',
    ]);
    expect(runner.arguments!.join(' '), isNot(contains('password')));
    expect(runner.cancelCalls, 1);
  });

  test('reports a missing helper before starting a process', () {
    final adapter = ProcessIosSideloadAdapter(
      helperPath: '/missing/helper',
      helperExists: (_) => false,
      runner: FakeHelperRunner(),
    );

    expect(
      adapter.status(),
      throwsA(
        isA<IosSideloadPlatformException>().having(
          (error) => error.code,
          'code',
          IosSideloadErrorCode.helperMissing,
        ),
      ),
    );
  });
}
