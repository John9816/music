import 'dart:convert';
import 'dart:io';

import 'ios_sideload/macos_signing.dart';

typedef HelperProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

Map<String, String> parseHelperOptions(List<String> arguments) {
  final result = <String, String>{
    'command': arguments.isEmpty ? 'status' : arguments.first,
  };
  for (var index = 1; index < arguments.length; index++) {
    final argument = arguments[index];
    if (!argument.startsWith('--') || argument == '--json') continue;
    if (index + 1 >= arguments.length ||
        arguments[index + 1].startsWith('--')) {
      continue;
    }
    final value = arguments[++index];
    switch (argument) {
      case '--ipa':
        result['ipa'] = value;
      case '--bundle-id':
        result['bundleId'] = value;
      case '--version':
        result['version'] = value;
      case '--build-number':
        result['buildNumber'] = value;
    }
  }
  return result;
}

Map<String, dynamic> buildStatusResponse({
  required String platform,
  required bool runtimeAvailable,
  required String runtimeMessage,
  List<Map<String, dynamic>> devices = const [],
}) {
  return {
    'ok': runtimeAvailable,
    'platform': platform,
    'helperVersion': '0.1.0',
    'message': runtimeMessage,
    'devices': devices,
    if (!runtimeAvailable)
      'code': platform == 'macOS' ? 'xcodeMissing' : 'appleDevicesMissing',
  };
}

Map<String, dynamic> buildUnsupportedResponse(String _) {
  return const {
    'ok': false,
    'code': 'helperMissing',
    'message': '本地签名引擎尚未配置，当前只能执行设备诊断',
  };
}

Future<Map<String, dynamic>> collectStatus({
  required bool isMacOS,
  required bool isWindows,
  HelperProcessRunner? run,
}) async {
  final runner = run ?? Process.run;
  if (isMacOS) {
    final xcode = await runner('/usr/bin/xcode-select', ['-p']);
    if (xcode.exitCode != 0) {
      return buildStatusResponse(
        platform: 'macOS',
        runtimeAvailable: false,
        runtimeMessage: '未找到 Xcode Command Line Tools',
      );
    }
    final devices = await runner('/usr/bin/xcrun', [
      'devicectl',
      'list',
      'devices',
    ]);
    if (devices.exitCode != 0) {
      return buildStatusResponse(
        platform: 'macOS',
        runtimeAvailable: false,
        runtimeMessage: 'xcrun devicectl 无法访问 iOS 设备',
      );
    }
    return buildStatusResponse(
      platform: 'macOS',
      runtimeAvailable: true,
      runtimeMessage: '本地诊断助手已就绪；签名引擎尚未配置',
      devices: _parseMacDevices(devices.stdout.toString()),
    );
  }

  if (isWindows) {
    final appleDevices = await runner('sc.exe', [
      'query',
      'Apple Mobile Device Service',
    ]);
    final bonjour = await runner('sc.exe', ['query', 'Bonjour Service']);
    if (appleDevices.exitCode != 0 || bonjour.exitCode != 0) {
      return buildStatusResponse(
        platform: 'Windows',
        runtimeAvailable: false,
        runtimeMessage: '缺少 Apple Devices/iTunes 或 Bonjour 服务',
      );
    }
    return buildStatusResponse(
      platform: 'Windows',
      runtimeAvailable: true,
      runtimeMessage: '本地诊断助手已就绪；签名引擎尚未配置',
    );
  }

  return buildStatusResponse(
    platform: 'unknown',
    runtimeAvailable: false,
    runtimeMessage: '当前平台不支持 iOS 本地助手',
  )..['code'] = 'helperMissing';
}

List<Map<String, dynamic>> _parseMacDevices(String output) {
  final devices = <Map<String, dynamic>>[];
  for (final line in const LineSplitter().convert(output)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty ||
        trimmed.startsWith('Name') ||
        trimmed.startsWith('---')) {
      continue;
    }
    final fields = trimmed.split(RegExp(r'\s{2,}'));
    if (fields.length < 2) continue;
    devices.add({
      'name': fields.first,
      'identifier': fields.length > 1 ? fields[1] : '',
      'connected': true,
      'trusted': true,
      'developerModeEnabled': true,
    });
  }
  return devices;
}

Future<void> main(List<String> arguments) async {
  final options = parseHelperOptions(arguments);
  final command = options['command']!;
  Map<String, dynamic> response;
  var code = 0;
  try {
    if (command == 'status') {
      response = Platform.isMacOS
          ? await MacIosSigningBackend().status(
              bundleIdentifier: options['bundleId'] ?? 'com.751152.duckMusic',
            )
          : await collectStatus(
              isMacOS: Platform.isMacOS,
              isWindows: Platform.isWindows,
            );
      code = response['ok'] == true ? 0 : 2;
    } else if (command == 'install' || command == 'refresh') {
      final ipaPath = options['ipa'];
      if (!Platform.isMacOS) {
        response = buildUnsupportedResponse(command);
      } else if (ipaPath == null || ipaPath.trim().isEmpty) {
        response = {
          'ok': false,
          'code': 'installFailed',
          'message': '缺少待签名 IPA 路径',
        };
      } else {
        response = await MacIosSigningBackend().install(
          ipaPath: ipaPath,
          bundleIdentifier: options['bundleId'] ?? 'com.751152.duckMusic',
          refreshing: command == 'refresh',
        );
      }
      code = 2;
      if (response['ok'] == true) code = 0;
    } else {
      response = {
        'ok': false,
        'code': 'unknown',
        'message': '未知命令：$command',
      };
      code = 2;
    }
  } on MacSigningException catch (error) {
    response = {
      'ok': false,
      'code': error.code,
      'message': error.message,
    };
    code = 2;
  } catch (error) {
    stderr.writeln('helper error: ${error.runtimeType}');
    response = {
      'ok': false,
      'code': 'unknown',
      'message': '诊断助手执行失败',
    };
    code = 2;
  }
  stdout.write(jsonEncode(response));
  stdout.write('\n');
  exitCode = code;
}
