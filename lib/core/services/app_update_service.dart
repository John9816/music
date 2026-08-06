import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import '../config/app_config.dart';

enum UpdateTarget { android, ios, macos, windows, unsupported }

enum UpdateCheckStatus { updateAvailable, upToDate, failed }

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
  AppUpdateService({http.Client? client}) : _client = client ?? http.Client();

  static const _androidUpdateChannel = MethodChannel('duckmusic/update');
  final http.Client _client;

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

  Future<UpdateCheckResult?> _checkAndroidManifest(String currentVersion) async {
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
        assetUrl = downloads[Abi.current().toString()]?.toString().trim();
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

    IOSink? sink;
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await _client.send(request).timeout(
            const Duration(seconds: 20),
          );
      if (response.statusCode != 200) return null;

      final directory = await getTemporaryDirectory();
      final extension = _extensionForUrl(url, resolvedTarget);
      final file = File('${directory.path}/duck_music_update$extension');
      sink = file.openWrite();
      final total = response.contentLength;
      var received = 0;
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
      onProgress?.call(1);
      return file.path;
    } catch (_) {
      return null;
    } finally {
      await sink?.close();
    }
  }

  Future<bool> installUpdate(String filePath) async {
    if (currentTarget == UpdateTarget.ios ||
        currentTarget == UpdateTarget.unsupported) {
      return false;
    }
    try {
      if (currentTarget == UpdateTarget.android) {
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
    } catch (_) {
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
          candidates.add((
            asset: asset,
            score: _assetScore(name, target, architecture.toLowerCase()),
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
    if (name.contains('universal')) return 100;
    final isArm64 = architecture.contains('arm64');
    final isX64 = architecture.contains('x64');
    if (isArm64 && (name.contains('arm64') || name.contains('aarch64'))) {
      return 90;
    }
    if (isX64 && (name.contains('x64') || name.contains('x86_64'))) {
      return 90;
    }
    if (target == UpdateTarget.android && name.contains('armeabi-v7a')) {
      return 10;
    }
    return 0;
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
