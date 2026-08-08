class IosSideloadManifest {
  IosSideloadManifest({
    required this.version,
    required this.buildNumber,
    required this.downloadUrl,
    required this.sha256,
    this.minimumOsVersion,
    this.publishedAt,
  });

  factory IosSideloadManifest.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    final buildNumber = json['buildNumber'];
    final downloadUrl = json['downloadUrl'];
    final hash = json['sha256'];
    if (version is! String || version.trim().isEmpty) {
      throw const FormatException('iOS 清单缺少 version');
    }
    if (buildNumber is! num || buildNumber <= 0) {
      throw const FormatException('iOS 清单缺少有效 buildNumber');
    }
    final uri = Uri.tryParse(downloadUrl is String ? downloadUrl : '');
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException('iOS 清单缺少有效 downloadUrl');
    }
    if (hash is! String || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hash)) {
      throw const FormatException('iOS 清单缺少有效 sha256');
    }

    DateTime? publishedAt;
    final rawPublishedAt = json['publishedAt'];
    if (rawPublishedAt != null) {
      if (rawPublishedAt is! String) {
        throw const FormatException('iOS 清单 publishedAt 格式错误');
      }
      publishedAt = DateTime.tryParse(rawPublishedAt)?.toUtc();
      if (publishedAt == null) {
        throw const FormatException('iOS 清单 publishedAt 格式错误');
      }
    }

    return IosSideloadManifest(
      version: version.trim(),
      buildNumber: buildNumber.toInt(),
      downloadUrl: uri,
      sha256: hash.toLowerCase(),
      minimumOsVersion: json['minimumOsVersion'] as String?,
      publishedAt: publishedAt,
    );
  }

  final String version;
  final int buildNumber;
  final Uri downloadUrl;
  final String sha256;
  final String? minimumOsVersion;
  final DateTime? publishedAt;
}

class IosSideloadDevice {
  const IosSideloadDevice({
    required this.name,
    required this.identifier,
    required this.connected,
    this.osVersion,
    this.trusted = false,
    this.developerModeEnabled = false,
  });

  final String name;
  final String identifier;
  final bool connected;
  final String? osVersion;
  final bool trusted;
  final bool developerModeEnabled;
}

class IosSideloadStatus {
  const IosSideloadStatus({
    this.accountLabel,
    this.signatureExpiresAt,
    this.devices = const [],
    this.errorCode,
    this.message,
  });

  final String? accountLabel;
  final DateTime? signatureExpiresAt;
  final List<IosSideloadDevice> devices;
  final IosSideloadErrorCode? errorCode;
  final String? message;

  bool get hasConnectedDevice => devices.any((device) => device.connected);

  bool needsRefresh(DateTime now) {
    final expiresAt = signatureExpiresAt;
    return expiresAt != null &&
        !expiresAt.isBefore(now) &&
        expiresAt.difference(now) <= const Duration(hours: 24);
  }

  IosSideloadStatus copyWith({
    String? accountLabel,
    DateTime? signatureExpiresAt,
    List<IosSideloadDevice>? devices,
    IosSideloadErrorCode? errorCode,
    String? message,
  }) {
    return IosSideloadStatus(
      accountLabel: accountLabel ?? this.accountLabel,
      signatureExpiresAt: signatureExpiresAt ?? this.signatureExpiresAt,
      devices: devices ?? this.devices,
      errorCode: errorCode ?? this.errorCode,
      message: message ?? this.message,
    );
  }
}

enum IosSideloadErrorCode {
  notConfigured,
  helperMissing,
  xcodeMissing,
  appleDevicesMissing,
  deviceUntrusted,
  developerModeRequired,
  profileExpired,
  installFailed,
  network,
  invalidManifest,
  busy,
  cancelled,
  unknown,
}

enum IosSideloadTaskState {
  idle,
  loading,
  installing,
  refreshing,
  success,
  failed
}
