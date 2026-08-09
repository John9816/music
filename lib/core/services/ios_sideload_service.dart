import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/ios_sideload.dart';

abstract class IosSideloadPlatformAdapter {
  Future<IosSideloadStatus> status();

  Future<IosSideloadStatus> install(
    IosSideloadManifest manifest,
    String ipaPath,
  );

  Future<IosSideloadStatus> refresh(
    IosSideloadManifest manifest,
    String ipaPath,
  );

  Future<void> cancel();
}

class IosSideloadPlatformException implements Exception {
  const IosSideloadPlatformException(this.code, this.message);

  final IosSideloadErrorCode code;
  final String message;

  @override
  String toString() => message;
}

class IosSideloadException implements Exception {
  const IosSideloadException(this.code, this.message, {this.cause});

  final IosSideloadErrorCode code;
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

abstract class IosSideloadStateStore {
  Future<bool> hasInstalledBuild();

  Future<void> saveInstalledBuild(String version);
}

/// Stores only a local installation marker; it never contains Apple credentials.
class FileIosSideloadStateStore implements IosSideloadStateStore {
  FileIosSideloadStateStore({String? path}) : _path = path ?? _defaultPath();

  final String _path;

  @override
  Future<bool> hasInstalledBuild() async {
    final file = File(_path);
    if (!await file.exists()) return false;
    try {
      final value = jsonDecode(await file.readAsString());
      return value is Map && value['installed'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> saveInstalledBuild(String version) async {
    final file = File(_path);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'installed': true,
        'version': version,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
  }

  static String _defaultPath() {
    final environment = Platform.environment;
    final root = Platform.isWindows
        ? (environment['APPDATA'] ??
            environment['USERPROFILE'] ??
            Directory.current.path)
        : (environment['HOME'] ?? Directory.current.path);
    return Platform.isWindows
        ? '$root${Platform.pathSeparator}DuckMusic${Platform.pathSeparator}ios-sideload.json'
        : '$root/Library/Application Support/DuckMusic/ios-sideload.json';
  }
}

class IosHelperCommandResult {
  const IosHelperCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

abstract class IosHelperCommandRunner {
  Future<IosHelperCommandResult> run(
    String executable,
    List<String> arguments,
  );

  Future<void> cancel();
}

class SystemIosHelperCommandRunner implements IosHelperCommandRunner {
  Process? _process;

  @override
  Future<IosHelperCommandResult> run(
    String executable,
    List<String> arguments,
  ) async {
    if (_process != null) {
      throw StateError('iOS helper process is already running');
    }
    final process = await Process.start(executable, arguments);
    _process = process;
    final stdoutFuture = utf8.decoder.bind(process.stdout).join();
    final stderrFuture = utf8.decoder.bind(process.stderr).join();
    try {
      final exitCode = await process.exitCode;
      return IosHelperCommandResult(
        exitCode: exitCode,
        stdout: await stdoutFuture,
        stderr: await stderrFuture,
      );
    } finally {
      _process = null;
    }
  }

  @override
  Future<void> cancel() async {
    _process?.kill(ProcessSignal.sigterm);
  }
}

class ProcessIosSideloadAdapter implements IosSideloadPlatformAdapter {
  ProcessIosSideloadAdapter({
    String? helperPath,
    bool Function(String path)? helperExists,
    IosHelperCommandRunner? runner,
  })  : helperPath = helperPath ?? resolveHelperPath(),
        _helperExists = helperExists ?? ((path) => File(path).existsSync()),
        _runner = runner ?? SystemIosHelperCommandRunner();

  final String? helperPath;
  final bool Function(String path) _helperExists;
  final IosHelperCommandRunner _runner;

  static String? resolveHelperPath({
    String configuredPath = AppConfig.iosSideloadHelperPath,
    Map<String, String>? environment,
    String? resolvedExecutable,
    bool? isMacOS,
    bool? isWindows,
    bool Function(String path)? fileExists,
  }) {
    final env = environment ?? Platform.environment;
    final executable = resolvedExecutable ?? Platform.resolvedExecutable;
    final onMacOS = isMacOS ?? Platform.isMacOS;
    final onWindows = isWindows ?? Platform.isWindows;
    final exists = fileExists ?? ((path) => File(path).existsSync());
    final candidates = <String>[
      if (configuredPath.trim().isNotEmpty) configuredPath.trim(),
      if ((env['DUCKMUSIC_IOS_HELPER'] ?? '').trim().isNotEmpty)
        env['DUCKMUSIC_IOS_HELPER']!.trim(),
      if (onMacOS)
        '${File(executable).parent.parent.path}/Resources/duckmusic-ios-helper',
      if (onWindows)
        '${File(executable).parent.path}\\duckmusic-ios-helper.exe',
    ];
    for (final candidate in candidates) {
      if (exists(candidate)) return candidate;
    }
    return null;
  }

  @override
  Future<IosSideloadStatus> status() => _invoke('status');

  @override
  Future<IosSideloadStatus> install(
    IosSideloadManifest manifest,
    String ipaPath,
  ) {
    return _invoke('install', manifest: manifest, ipaPath: ipaPath);
  }

  @override
  Future<IosSideloadStatus> refresh(
    IosSideloadManifest manifest,
    String ipaPath,
  ) {
    return _invoke('refresh', manifest: manifest, ipaPath: ipaPath);
  }

  @override
  Future<void> cancel() => _runner.cancel();

  Future<IosSideloadStatus> _invoke(
    String command, {
    IosSideloadManifest? manifest,
    String? ipaPath,
  }) async {
    final executable = helperPath;
    if (executable == null || !_helperExists(executable)) {
      throw const IosSideloadPlatformException(
        IosSideloadErrorCode.helperMissing,
        '未找到 DuckMusic 本地 iOS 签名助手',
      );
    }
    final arguments = <String>[command, '--json'];
    if (manifest != null && ipaPath != null) {
      arguments.addAll([
        '--ipa',
        ipaPath,
        '--version',
        manifest.version,
        '--build-number',
        manifest.buildNumber.toString(),
        '--bundle-id',
        'com.751152.duckMusic',
      ]);
    }
    final result = await _runner.run(executable, arguments);
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(result.stdout.trim());
      if (decoded is! Map) throw const FormatException();
      json = decoded.map((key, value) => MapEntry(key.toString(), value));
    } catch (_) {
      throw IosSideloadPlatformException(
        IosSideloadErrorCode.unknown,
        result.stderr.trim().isEmpty ? '本地签名助手返回了无效结果' : result.stderr.trim(),
      );
    }
    if (json['ok'] != true || result.exitCode != 0) {
      throw IosSideloadPlatformException(
        _iosSideloadErrorCodeFromName(json['code']?.toString() ?? ''),
        json['message']?.toString() ?? '本地签名助手执行失败',
      );
    }
    return _iosSideloadStatusFromMap(json);
  }
}

IosSideloadStatus _iosSideloadStatusFromMap(Map<String, dynamic> map) {
  final rawExpiry = map['signatureExpiresAt'];
  final expiry =
      rawExpiry is String ? DateTime.tryParse(rawExpiry)?.toUtc() : null;
  final rawDevices = map['devices'];
  final devices = rawDevices is List
      ? rawDevices
          .whereType<Map>()
          .map(
            (device) => IosSideloadDevice(
              name: device['name']?.toString() ?? 'iPhone',
              identifier: device['identifier']?.toString() ?? '',
              connected: device['connected'] == true,
              osVersion: device['osVersion']?.toString(),
              trusted: device['trusted'] == true,
              developerModeEnabled: device['developerModeEnabled'] == true,
            ),
          )
          .toList(growable: false)
      : const <IosSideloadDevice>[];
  return IosSideloadStatus(
    accountLabel: map['accountLabel']?.toString(),
    signatureExpiresAt: expiry,
    devices: devices,
    message: map['message']?.toString(),
  );
}

IosSideloadErrorCode _iosSideloadErrorCodeFromName(String value) {
  return IosSideloadErrorCode.values.firstWhere(
    (code) => code.name == value,
    orElse: () => IosSideloadErrorCode.unknown,
  );
}

class MethodChannelIosSideloadAdapter implements IosSideloadPlatformAdapter {
  MethodChannelIosSideloadAdapter({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('com.duckmusic.ios_sideload');

  final MethodChannel _channel;

  @override
  Future<IosSideloadStatus> status() async {
    final result = await _invoke('status');
    return _iosSideloadStatusFromMap(result);
  }

  @override
  Future<IosSideloadStatus> install(
    IosSideloadManifest manifest,
    String ipaPath,
  ) async {
    final result = await _invoke('install', <String, Object?>{
      'version': manifest.version,
      'buildNumber': manifest.buildNumber,
      'downloadUrl': manifest.downloadUrl.toString(),
      'ipaPath': ipaPath,
    });
    return _iosSideloadStatusFromMap(result);
  }

  @override
  Future<IosSideloadStatus> refresh(
    IosSideloadManifest manifest,
    String ipaPath,
  ) async {
    final result = await _invoke('refresh', <String, Object?>{
      'version': manifest.version,
      'buildNumber': manifest.buildNumber,
      'ipaPath': ipaPath,
    });
    return _iosSideloadStatusFromMap(result);
  }

  @override
  Future<void> cancel() async {
    await _invoke('cancel');
  }

  Future<Map<String, dynamic>> _invoke(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      final raw = await _channel.invokeMethod<Object?>(method, arguments);
      if (raw is Map) {
        return raw.map((key, value) => MapEntry(key.toString(), value));
      }
      return const <String, dynamic>{};
    } on MissingPluginException {
      throw const IosSideloadPlatformException(
        IosSideloadErrorCode.helperMissing,
        '未找到本地 iOS 签名助手',
      );
    } on PlatformException catch (error) {
      throw IosSideloadPlatformException(
        _iosSideloadErrorCodeFromName(error.code),
        error.message ?? '本地 iOS 助手执行失败',
      );
    }
  }
}

class IosSideloadService extends ChangeNotifier {
  IosSideloadService({
    http.Client? client,
    IosSideloadPlatformAdapter? adapter,
    String? manifestUrl,
    IosSideloadStateStore? stateStore,
    DateTime Function()? now,
    bool? desktopPlatform,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _adapter = adapter ?? ProcessIosSideloadAdapter(),
        manifestUrl = manifestUrl ?? AppConfig.iosSideloadManifestUrl,
        _stateStore = stateStore,
        _now = now ?? (() => DateTime.now().toUtc()),
        _desktopPlatform =
            desktopPlatform ?? (Platform.isMacOS || Platform.isWindows);

  final http.Client _client;
  final bool _ownsClient;
  final IosSideloadPlatformAdapter _adapter;
  final String manifestUrl;
  final IosSideloadStateStore? _stateStore;
  final DateTime Function() _now;
  final bool _desktopPlatform;

  IosSideloadManifest? manifest;
  IosSideloadStatus status = const IosSideloadStatus();
  IosSideloadTaskState taskState = IosSideloadTaskState.idle;
  bool _taskInProgress = false;

  Future<IosSideloadManifest> loadManifest() async {
    if (manifestUrl.trim().isEmpty) {
      return _fail(
        const IosSideloadException(
          IosSideloadErrorCode.notConfigured,
          'ECS iOS 清单地址尚未配置',
        ),
      );
    }

    try {
      final response = await _client
          .get(Uri.parse(manifestUrl))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw IosSideloadException(
          IosSideloadErrorCode.network,
          'ECS iOS 清单请求失败（HTTP ${response.statusCode}）',
        );
      }
      final decoded = jsonDecode(response.body);
      final raw = decoded is Map && decoded['data'] is Map
          ? decoded['data'] as Map
          : decoded;
      if (raw is! Map) {
        throw const IosSideloadException(
          IosSideloadErrorCode.invalidManifest,
          'ECS iOS 清单格式不正确',
        );
      }
      final parsed = IosSideloadManifest.fromJson(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      manifest = parsed;
      status = const IosSideloadStatus();
      taskState = IosSideloadTaskState.idle;
      notifyListeners();
      return parsed;
    } on IosSideloadException catch (error) {
      return _fail(error);
    } on FormatException catch (error) {
      return _fail(
        IosSideloadException(
          IosSideloadErrorCode.invalidManifest,
          'ECS iOS 清单解析失败',
          cause: error,
        ),
      );
    } catch (error) {
      return _fail(
        IosSideloadException(
          IosSideloadErrorCode.network,
          '无法连接 ECS iOS 清单',
          cause: error,
        ),
      );
    }
  }

  Future<IosSideloadStatus> refreshStatus() async {
    try {
      status = await _adapter.status();
      notifyListeners();
      return status;
    } on IosSideloadPlatformException catch (error) {
      status = IosSideloadStatus(
        errorCode: error.code,
        message: error.message,
      );
      taskState = IosSideloadTaskState.failed;
      notifyListeners();
      return status;
    }
  }

  Future<void> installLatest() async {
    await _runTask(IosSideloadTaskState.installing, (latest) {
      return _withVerifiedIpa(
        latest,
        (ipaPath) => _adapter.install(latest, ipaPath),
      );
    });
  }

  Future<void> refreshInstalled() async {
    await _runTask(
      IosSideloadTaskState.refreshing,
      (latest) => _withVerifiedIpa(
        latest,
        (ipaPath) => _adapter.refresh(latest, ipaPath),
      ),
    );
  }

  Future<void> cancel() async {
    await _adapter.cancel();
    if (_taskInProgress) {
      _taskInProgress = false;
      taskState = IosSideloadTaskState.idle;
      notifyListeners();
    }
  }

  /// Runs once when the desktop app starts. iOS cannot renew its own signature.
  Future<void> autoRefreshIfNeeded() async {
    final store = _stateStore;
    if (store == null || !_desktopPlatform) return;
    if (!await store.hasInstalledBuild()) return;
    try {
      if (manifest == null) await loadManifest();
      final current = await refreshStatus();
      if (current.needsRefresh(_now())) await refreshInstalled();
    } on IosSideloadException {
      // Diagnostics are already published on the service for the settings page.
    }
  }

  Future<void> _runTask(
    IosSideloadTaskState state,
    Future<IosSideloadStatus> Function(IosSideloadManifest latest) operation,
  ) async {
    if (_taskInProgress) {
      throw const IosSideloadException(
        IosSideloadErrorCode.busy,
        '已有一个 iOS 任务正在执行',
      );
    }
    _taskInProgress = true;
    taskState = state;
    notifyListeners();
    try {
      final latest = manifest ?? await loadManifest();
      status = await operation(latest);
      taskState = IosSideloadTaskState.success;
      final store = _stateStore;
      if (store != null) await store.saveInstalledBuild(latest.version);
      notifyListeners();
    } on IosSideloadException catch (error) {
      _setFailure(error);
    } on IosSideloadPlatformException catch (error) {
      _setFailure(
        IosSideloadException(error.code, error.message, cause: error),
      );
    } catch (error) {
      _setFailure(
        IosSideloadException(
          IosSideloadErrorCode.installFailed,
          'iOS 安装任务失败',
          cause: error,
        ),
      );
    } finally {
      _taskInProgress = false;
    }
  }

  Future<Uint8List> _downloadAndVerify(IosSideloadManifest latest) async {
    final response = await _client
        .get(latest.downloadUrl)
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw IosSideloadException(
        IosSideloadErrorCode.network,
        'IPA 下载失败（HTTP ${response.statusCode}）',
      );
    }
    final actual = sha256.convert(response.bodyBytes).toString();
    if (actual != latest.sha256) {
      throw const IosSideloadException(
        IosSideloadErrorCode.invalidManifest,
        'IPA 校验值不匹配，已停止安装',
      );
    }
    return response.bodyBytes;
  }

  Future<IosSideloadStatus> _withVerifiedIpa(
    IosSideloadManifest latest,
    Future<IosSideloadStatus> Function(String ipaPath) operation,
  ) async {
    final bytes = await _downloadAndVerify(latest);
    final temporary = await Directory.systemTemp.createTemp('duckmusic-ios-');
    final ipa = File('${temporary.path}/DuckMusic-${latest.version}.ipa');
    try {
      await ipa.writeAsBytes(bytes, flush: true);
      return await operation(ipa.path);
    } finally {
      if (await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
    }
  }

  Never _fail(IosSideloadException error) {
    _setFailure(error);
    throw error;
  }

  void _setFailure(IosSideloadException error) {
    taskState = IosSideloadTaskState.failed;
    status = IosSideloadStatus(
      accountLabel: status.accountLabel,
      signatureExpiresAt: status.signatureExpiresAt,
      devices: status.devices,
      errorCode: error.code,
      message: error.message,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    if (_ownsClient) _client.close();
    super.dispose();
  }
}
