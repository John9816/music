import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import '../config/app_config.dart';

enum UpdateTarget { android, ios, macos, windows, unsupported }

enum UpdateCheckStatus { updateAvailable, upToDate, failed }

class AppInstallIdentity {
  const AppInstallIdentity(
      {required this.packageName,
      required this.version,
      required this.buildNumber,
      required this.production});
  final String packageName;
  final String version;
  final int buildNumber;
  final bool production;
  String get description =>
      '$version ($buildNumber) · ${production ? '正式版' : '开发版'}';
}

class UpdateRelease {
  const UpdateRelease({
    required this.version,
    required this.releasePageUrl,
    this.assetUrl,
  });

  final String version;
  final String releasePageUrl;
  final String? assetUrl;
}

class UpdateCheckResult {
  const UpdateCheckResult._({
    required this.status,
    this.release,
    this.message,
  });

  const UpdateCheckResult.available(UpdateRelease release)
      : this._(
          status: UpdateCheckStatus.updateAvailable,
          release: release,
        );

  const UpdateCheckResult.upToDate(UpdateRelease release)
      : this._(
          status: UpdateCheckStatus.upToDate,
          release: release,
        );

  const UpdateCheckResult.failed(String message)
      : this._(
          status: UpdateCheckStatus.failed,
          message: message,
        );

  final UpdateCheckStatus status;
  final UpdateRelease? release;
  final String? message;
}

/// Checks GitHub Releases and hands installation off to the operating system.
///
/// Android opens the downloaded APK in the package installer. macOS opens a
/// DMG/PKG and Windows opens an EXE/MSI. iOS is required to update through the
/// App Store, so it never downloads an installer inside the app.
class AppUpdateService {
  AppUpdateService(
      {http.Client? client,
      Future<AppInstallIdentity?> Function()? androidIdentityLoader})
      : _client = client ?? http.Client(),
        _androidIdentityLoader = androidIdentityLoader ?? androidIdentity;

  static const _androidUpdateChannel = MethodChannel('duckmusic/update');
  final http.Client _client;
  final Future<AppInstallIdentity?> Function() _androidIdentityLoader;
  String? installError;

  static Future<AppInstallIdentity?> androidIdentity() async {
    if (!Platform.isAndroid) return null;
    try {
      final data = await _androidUpdateChannel
          .invokeMapMethod<String, dynamic>('getAppIdentity');
      if (data == null) return null;
      return AppInstallIdentity(
        packageName: data['packageName'] as String,
        version: data['version'] as String,
        buildNumber: (data['buildNumber'] as num).toInt(),
        production: data['production'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<UpdateCheckResult> checkLatest({
    String currentVersion = AppConfig.appVersion,
    UpdateTarget? target,
    String iosAppStoreId = AppConfig.iosAppStoreId,
  }) async {
    final resolvedTarget = target ?? currentTarget;
    if (resolvedTarget == UpdateTarget.ios) {
      return _checkAppStore(currentVersion, iosAppStoreId);
    }
    if (resolvedTarget == UpdateTarget.unsupported) {
      return const UpdateCheckResult.failed('当前平台暂不支持在线更新');
    }

    if (resolvedTarget == UpdateTarget.android) {
      final identity = await _androidIdentityLoader();
      if (identity != null && !identity.production) {
        return const UpdateCheckResult.failed(
            '当前是开发版，不能通过正式通道覆盖更新。请打开名称不带「开发版」的正式应用。');
      }
      currentVersion = identity?.version ?? currentVersion;
      final ecsResult = await _checkAndroidManifest(currentVersion);
      if (ecsResult != null) return ecsResult;
    }

    try {
      final response = await _client.get(
        Uri.parse(
          'https://api.github.com/repos/${AppConfig.updateRepository}/releases?per_page=20',
        ),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'DuckMusic-Flutter',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        return UpdateCheckResult.failed(
          '更新服务返回 ${response.statusCode}',
        );
      }

      final decoded = jsonDecode(response.body);
      final json = _selectRelease(decoded);
      if (json == null) {
        return const UpdateCheckResult.failed('未找到适用于当前应用的更新版本');
      }
      final tag = json['tag_name']?.toString().trim();
      final version = tag?.substring(AppConfig.updateReleaseTagPrefix.length);
      final releasePageUrl = json['html_url']?.toString().trim();
      if (version == null ||
          version.isEmpty ||
          releasePageUrl == null ||
          releasePageUrl.isEmpty) {
        return const UpdateCheckResult.failed('更新信息格式不正确');
      }

      final release = UpdateRelease(
        version: version,
        releasePageUrl: releasePageUrl,
        assetUrl: selectAssetUrl(
          json['assets'],
          resolvedTarget,
          requiredNamePrefix: AppConfig.updateAssetPrefix,
          architecture: currentArchitecture,
        ),
      );
      return isNewer(version, currentVersion)
          ? UpdateCheckResult.available(release)
          : UpdateCheckResult.upToDate(release);
    } on FormatException {
      return const UpdateCheckResult.failed('更新信息无法解析');
    } catch (_) {
      return const UpdateCheckResult.failed('无法连接更新服务');
    }
  }

  Future<UpdateCheckResult?> _checkAndroidManifest(
      String currentVersion) async {
    try {
      final response = await _client.get(
        Uri.parse('https://api.751152.xyz/updates/latest.json'),
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'DuckMusic-Flutter',
        },
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body);
      if (json is! Map) return null;
      final manifest = Map<String, dynamic>.from(json);
      final version = manifest['version']?.toString().trim();
      if (version == null || version.isEmpty) return null;

      final downloads = manifest['downloads'];
      String? assetUrl;
      if (downloads is Map) {
        assetUrl = downloads[androidAbiName(Abi.current())]?.toString().trim();
      }
      assetUrl ??= manifest['downloadUrl']?.toString().trim();
      if (assetUrl?.isEmpty == true) assetUrl = null;

      final release = UpdateRelease(
        version: version,
        releasePageUrl: 'https://api.751152.xyz/updates/latest.json',
        assetUrl: assetUrl,
      );
      return isNewer(version, currentVersion)
          ? UpdateCheckResult.available(release)
          : UpdateCheckResult.upToDate(release);
    } on FormatException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<UpdateCheckResult> _checkAppStore(
    String currentVersion,
    String appStoreId,
  ) async {
    if (appStoreId.isEmpty) {
      return const UpdateCheckResult.failed('iOS App Store ID 尚未配置');
    }
    try {
      final response = await _client.get(
        Uri.https(
          'itunes.apple.com',
          '/lookup',
          {'id': appStoreId, 'country': 'cn'},
        ),
        headers: const {'User-Agent': 'DuckMusic-Flutter'},
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        return UpdateCheckResult.failed(
          'App Store 返回 ${response.statusCode}',
        );
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final results = json['results'];
      if (results is! List || results.isEmpty || results.first is! Map) {
        return const UpdateCheckResult.failed('App Store 中未找到此应用');
      }
      final app = Map<String, dynamic>.from(results.first as Map);
      final version = app['version']?.toString().trim();
      final storeUrl = app['trackViewUrl']?.toString().trim();
      if (version == null ||
          version.isEmpty ||
          storeUrl == null ||
          storeUrl.isEmpty) {
        return const UpdateCheckResult.failed('App Store 更新信息格式不正确');
      }
      final release = UpdateRelease(
        version: version,
        releasePageUrl: storeUrl,
      );
      return isNewer(version, currentVersion)
          ? UpdateCheckResult.available(release)
          : UpdateCheckResult.upToDate(release);
    } on FormatException {
      return const UpdateCheckResult.failed('App Store 更新信息无法解析');
    } catch (_) {
      return const UpdateCheckResult.failed('无法连接 App Store');
    }
  }

  /// 下载更新包，支持断点续传与断流自动重试。
  ///
  /// 中间结果保存在 `<file>.part`，中断后再次进入会从已下载字节处继续，
  /// 而不是从头开始。若服务端忽略 Range（返回 200）则自动回退为整包重下；
  /// 若服务端声明了不同的起始偏移，同样丢弃本地片段重来，避免拼出坏包。
  /// 文件名带 URL 指纹，换版本后不会错误复用上个版本的残留片段。
  Future<String?> downloadUpdate(
    String url, {
    ValueChanged<double>? onProgress,
    UpdateTarget? target,
  }) async {
    final resolvedTarget = target ?? currentTarget;
    if (resolvedTarget == UpdateTarget.ios ||
        resolvedTarget == UpdateTarget.unsupported) {
      return null;
    }

    final directory = await getTemporaryDirectory();
    final extension = _extensionForUrl(url, resolvedTarget);
    final fingerprint =
        sha1.convert(utf8.encode(url)).toString().substring(0, 10);
    final partFile = File(
      '${directory.path}/duck_music_update_$fingerprint$extension.part',
    );
    final targetFile = File('${directory.path}/duck_music_update$extension');

    const maxAttempts = 4;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final completed = await _downloadOnce(
        url: url,
        partFile: partFile,
        targetFile: targetFile,
        onProgress: onProgress,
      );
      if (completed != null) return completed;
      if (attempt < maxAttempts) {
        // 1s、2s、4s 退避，给弱网留出恢复时间
        await Future<void>.delayed(Duration(seconds: 1 << (attempt - 1)));
      }
    }
    return null;
  }

  /// 单次下载尝试。成功返回最终路径，失败返回 null 并保留 `.part` 供续传。
  Future<String?> _downloadOnce({
    required String url,
    required File partFile,
    required File targetFile,
    ValueChanged<double>? onProgress,
  }) async {
    var existing = 0;
    try {
      if (await partFile.exists()) existing = await partFile.length();
    } catch (_) {
      existing = 0;
    }

    IOSink? sink;
    try {
      final request = http.Request('GET', Uri.parse(url));
      request.headers['User-Agent'] = 'DuckMusic-Flutter';
      // 禁止透明压缩：否则 contentLength 是压缩后长度、流是解压后数据，
      // 长度校验和断点偏移都会错位
      request.headers['Accept-Encoding'] = 'identity';
      if (existing > 0) request.headers['Range'] = 'bytes=$existing-';

      final response = await _client.send(request).timeout(
            const Duration(seconds: 20),
          );

      var start = existing;
      int? total = response.contentLength == null
          ? null
          : response.contentLength! + existing;

      if (response.statusCode == 200) {
        // 服务端忽略了 Range，只能整包重下
        start = 0;
        total = response.contentLength;
        if (await partFile.exists()) await partFile.delete();
      } else if (response.statusCode == 206) {
        final declaredStart =
            _rangeStart(response.headers['content-range']);
        if (declaredStart != null && declaredStart != existing) {
          // 偏移对不上，本地片段不可用
          start = 0;
          total = response.contentLength == null
              ? null
              : response.contentLength! + declaredStart;
          if (await partFile.exists()) await partFile.delete();
        }
      } else if (response.statusCode == 416) {
        // 本地残留超出远端长度，丢弃后由上层重试
        if (await partFile.exists()) await partFile.delete();
        return null;
      } else {
        return null;
      }

      sink = partFile.openWrite(
        mode: start > 0 ? FileMode.append : FileMode.write,
      );
      var received = start;
      if (total != null && total > 0) {
        onProgress?.call((received / total).clamp(0, 1));
      }
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total != null && total > 0) {
          onProgress?.call((received / total).clamp(0, 1));
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;

      // 长度对不上说明连接被截断，保留片段等待续传。
      // 若服务端无视 identity 仍返回压缩内容，长度基准不可靠，跳过校验。
      final encoding = response.headers['content-encoding'];
      final compressed = encoding != null && encoding != 'identity';
      if (!compressed && total != null && total > 0 && received != total) {
        return null;
      }

      if (await targetFile.exists()) await targetFile.delete();
      await partFile.rename(targetFile.path);
      onProgress?.call(1);
      return targetFile.path;
    } catch (_) {
      return null;
    } finally {
      try {
        await sink?.close();
      } catch (_) {
        // 关闭失败不影响续传：已落盘的字节仍然有效
      }
    }
  }

  /// 从 `Content-Range: bytes 100-999/1000` 中取出起始偏移。
  int? _rangeStart(String? contentRange) {
    if (contentRange == null) return null;
    final match = RegExp(r'bytes\s+(\d+)').firstMatch(contentRange);
    if (match == null) return null;
    return int.tryParse(match.group(1) ?? '');
  }

  Future<bool> installUpdate(String filePath, {UpdateTarget? target}) async {
    installError = null;
    final resolvedTarget = target ?? currentTarget;
    if (resolvedTarget == UpdateTarget.ios ||
        resolvedTarget == UpdateTarget.unsupported) {
      return false;
    }
    try {
      if (resolvedTarget == UpdateTarget.android) {
        return await _androidUpdateChannel.invokeMethod<bool>(
              'installApk',
              {'path': filePath},
            ) ??
            false;
      }
      return launcher.launchUrl(
        Uri.file(filePath),
        mode: launcher.LaunchMode.externalApplication,
      );
    } on PlatformException catch (error) {
      installError = error.message ?? '安装包校验失败';
      return false;
    } catch (_) {
      installError = '无法打开系统安装器，请重试';
      return false;
    }
  }

  Future<bool> openReleaseDestination(UpdateRelease release) async {
    final uri = Uri.tryParse(release.releasePageUrl);
    if (uri == null || !await launcher.canLaunchUrl(uri)) return false;
    return launcher.launchUrl(
      uri,
      mode: launcher.LaunchMode.externalApplication,
    );
  }

  static UpdateTarget get currentTarget {
    if (Platform.isAndroid) return UpdateTarget.android;
    if (Platform.isIOS) return UpdateTarget.ios;
    if (Platform.isMacOS) return UpdateTarget.macos;
    if (Platform.isWindows) return UpdateTarget.windows;
    return UpdateTarget.unsupported;
  }

  static String get currentArchitecture =>
      Abi.current().toString().toLowerCase();

  @visibleForTesting
  static String androidAbiName(Abi abi) {
    return switch (abi) {
      Abi.androidArm64 => 'arm64-v8a',
      Abi.androidArm => 'armeabi-v7a',
      Abi.androidX64 => 'x86_64',
      _ => abi.toString().toLowerCase(),
    };
  }

  static Map<String, dynamic>? _selectRelease(Object? rawReleases) {
    if (rawReleases is! List) return null;
    for (final rawRelease in rawReleases.whereType<Map>()) {
      final release = Map<String, dynamic>.from(rawRelease);
      final tag = release['tag_name']?.toString() ?? '';
      if (tag.startsWith(AppConfig.updateReleaseTagPrefix) &&
          release['draft'] != true &&
          release['prerelease'] != true) {
        return release;
      }
    }
    return null;
  }

  @visibleForTesting
  static String? selectAssetUrl(
    Object? rawAssets,
    UpdateTarget target, {
    String requiredNamePrefix = '',
    String architecture = '',
  }) {
    if (target == UpdateTarget.ios || target == UpdateTarget.unsupported) {
      return null;
    }
    final assets = rawAssets is List
        ? rawAssets.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : const <Map<String, dynamic>>[];
    final requiredPrefix = requiredNamePrefix.toLowerCase();
    final extensions = _preferredExtensions(target);
    for (final extension in extensions) {
      final candidates = <({Map<String, dynamic> asset, int score})>[];
      for (final asset in assets) {
        final name = asset['name']?.toString().toLowerCase() ?? '';
        final url = asset['browser_download_url']?.toString();
        if (name.endsWith(extension) &&
            (extension != '.zip' || _nameMatchesTarget(name, target)) &&
            (requiredPrefix.isEmpty || name.startsWith(requiredPrefix)) &&
            !name.contains('debug') &&
            url != null &&
            url.isNotEmpty) {
          final score = _assetScore(name, target, architecture.toLowerCase());
          if (score < 0) continue;
          candidates.add((
            asset: asset,
            score: score,
          ));
        }
      }
      if (candidates.isNotEmpty) {
        candidates.sort((a, b) => b.score.compareTo(a.score));
        return candidates.first.asset['browser_download_url']?.toString();
      }
    }
    return null;
  }

  static int _assetScore(
    String name,
    UpdateTarget target,
    String architecture,
  ) {
    if (target == UpdateTarget.android) {
      final assetAbi = _androidAbi(name);
      if (assetAbi != null) {
        return assetAbi == _androidAbi(architecture) ? 110 : -1;
      }
      return name.contains('universal') ? 100 : 0;
    }
    if (name.contains('universal')) return 100;
    final isArm64 = architecture.contains('arm64');
    final isX64 = architecture.contains('x64');
    if (isArm64 && (name.contains('arm64') || name.contains('aarch64'))) {
      return 90;
    }
    if (isX64 && (name.contains('x64') || name.contains('x86_64'))) {
      return 90;
    }
    return 0;
  }

  static String? _androidAbi(String value) {
    final match = RegExp(
      r'(?:^|[-_.])(arm64-v8a|arm64|aarch64|armeabi-v7a|armv7|arm|x86_64|x64|x86|ia32)(?:[-_.]|$)',
    ).firstMatch(value.replaceFirst(RegExp(r'^android_?'), ''));
    return switch (match?.group(1)) {
      'arm64-v8a' || 'arm64' || 'aarch64' => 'arm64-v8a',
      'armeabi-v7a' || 'armv7' || 'arm' => 'armeabi-v7a',
      'x86_64' || 'x64' => 'x86_64',
      'x86' || 'ia32' => 'x86',
      _ => null,
    };
  }

  static List<String> _preferredExtensions(UpdateTarget target) {
    return switch (target) {
      UpdateTarget.android => const ['.apk'],
      UpdateTarget.macos => const ['.dmg', '.pkg', '.zip'],
      UpdateTarget.windows => const ['.exe', '.msi', '.zip'],
      UpdateTarget.ios || UpdateTarget.unsupported => const [],
    };
  }

  static String _extensionForUrl(String url, UpdateTarget target) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    return _preferredExtensions(target).firstWhere(
      path.endsWith,
      orElse: () => _preferredExtensions(target).first,
    );
  }

  static bool _nameMatchesTarget(String name, UpdateTarget target) {
    return switch (target) {
      UpdateTarget.macos => name.contains('mac') || name.contains('darwin'),
      UpdateTarget.windows => name.contains('win'),
      UpdateTarget.android => name.contains('android') || name.contains('apk'),
      UpdateTarget.ios || UpdateTarget.unsupported => false,
    };
  }

  static bool isNewer(String latest, String current) {
    List<int> parts(String value) => RegExp(r'\d+')
        .allMatches(value)
        .take(4)
        .map((match) => int.parse(match.group(0)!))
        .toList();

    final latestParts = parts(latest);
    final currentParts = parts(current);
    final length = latestParts.length > currentParts.length
        ? latestParts.length
        : currentParts.length;
    for (var index = 0; index < length; index++) {
      final latestPart = index < latestParts.length ? latestParts[index] : 0;
      final currentPart = index < currentParts.length ? currentParts[index] : 0;
      if (latestPart != currentPart) return latestPart > currentPart;
    }
    return false;
  }
}
