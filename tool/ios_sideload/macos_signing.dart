import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

typedef MacCommandRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

class MacSigningException implements Exception {
  const MacSigningException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

class MacSigningIdentity {
  const MacSigningIdentity({required this.sha1, required this.label});

  final String sha1;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is MacSigningIdentity && sha1 == other.sha1 && label == other.label;

  @override
  int get hashCode => Object.hash(sha1, label);
}

class MacProvisioningProfile {
  const MacProvisioningProfile({
    required this.path,
    required this.name,
    required this.uuid,
    required this.teamIdentifier,
    required this.applicationIdentifier,
    required this.expirationDate,
    required this.provisionedDevices,
    required this.developerCertificateSha1s,
  });

  final String path;
  final String name;
  final String uuid;
  final String teamIdentifier;
  final String applicationIdentifier;
  final DateTime expirationDate;
  final List<String> provisionedDevices;
  final List<String> developerCertificateSha1s;

  String get bundleIdentifier {
    final prefix = '$teamIdentifier.';
    return applicationIdentifier.startsWith(prefix)
        ? applicationIdentifier.substring(prefix.length)
        : applicationIdentifier;
  }
}

class MacIosDevice {
  const MacIosDevice({
    required this.identifier,
    required this.udid,
    required this.name,
    required this.connected,
    required this.paired,
    required this.developerModeEnabled,
    this.osVersion,
  });

  final String identifier;
  final String udid;
  final String name;
  final bool connected;
  final bool paired;
  final bool developerModeEnabled;
  final String? osVersion;
}

class MacSigningContext {
  const MacSigningContext({
    required this.identity,
    required this.profile,
    required this.device,
  });

  final MacSigningIdentity identity;
  final MacProvisioningProfile profile;
  final MacIosDevice device;
}

class MacIosSigningBackend {
  MacIosSigningBackend({
    MacCommandRunner? run,
    String? homeDirectory,
    DateTime Function()? now,
  })  : _run = run ?? Process.run,
        _homeDirectory = homeDirectory ??
            (Platform.environment['HOME'] ?? Directory.current.path),
        _now = now ?? (() => DateTime.now().toUtc());

  final MacCommandRunner _run;
  final String _homeDirectory;
  final DateTime Function() _now;

  Future<Map<String, dynamic>> status({
    String bundleIdentifier = 'com.751152.duckMusic',
  }) async {
    final identitiesResult = await _run('/usr/bin/security', [
      'find-identity',
      '-v',
      '-p',
      'codesigning',
    ]);
    if (identitiesResult.exitCode != 0) {
      return _errorResponse(
        code: 'helperMissing',
        message: '无法读取本机 Apple Development 签名证书',
      );
    }
    final identities = parseMacSigningIdentities(
      identitiesResult.stdout.toString(),
    );
    final devices = await _listDevices();
    final profiles = await _loadProfiles();
    final validProfile = _chooseProfileForStatus(
      bundleIdentifier: bundleIdentifier,
      identities: identities,
      profiles: profiles,
    );
    final base = <String, dynamic>{
      'ok': false,
      'platform': 'macOS',
      'helperVersion': '0.2.0',
      'accountLabel': identities.firstOrNull?.label,
      'signatureExpiresAt':
          validProfile?.expirationDate.toUtc().toIso8601String(),
      'devices': devices.map(_deviceToJson).toList(growable: false),
    };

    if (validProfile == null) {
      return {
        ...base,
        'code': 'profileExpired',
        'message': '未找到与 DuckMusic 和本机证书匹配的有效描述文件',
      };
    }
    if (devices.isEmpty) {
      return {
        ...base,
        'code': 'appleDevicesMissing',
        'message': '未找到已连接的实体 iPhone',
      };
    }
    final paired = devices.where((device) => device.paired).toList();
    if (paired.isEmpty) {
      return {
        ...base,
        'code': 'deviceUntrusted',
        'message': '请先在 iPhone 上信任这台 Mac',
      };
    }
    final online = paired.where((device) => device.connected).toList();
    if (online.isEmpty) {
      return {
        ...base,
        'code': 'appleDevicesMissing',
        'message': '已配对的 iPhone 当前不在线，请通过 USB 或受信任的 Wi-Fi 连接',
      };
    }
    if (online.every((device) => !device.developerModeEnabled)) {
      return {
        ...base,
        'code': 'developerModeRequired',
        'message': '请在 iPhone 设置中开启开发者模式',
      };
    }
    return {
      ...base,
      'ok': true,
      'message': '本机签名环境和已配对 iPhone 已就绪',
    };
  }

  Future<Map<String, dynamic>> install({
    required String ipaPath,
    String bundleIdentifier = 'com.751152.duckMusic',
    bool refreshing = false,
  }) async {
    final identitiesResult = await _run('/usr/bin/security', [
      'find-identity',
      '-v',
      '-p',
      'codesigning',
    ]);
    final identities = parseMacSigningIdentities(
      identitiesResult.stdout.toString(),
    );
    final devices = await _listDevices();
    final profiles = await _loadProfiles();
    final context = selectMacSigningContext(
      bundleIdentifier: bundleIdentifier,
      identities: identities,
      profiles: profiles,
      devices: devices,
      now: _now(),
    );
    final ipa = File(ipaPath);
    if (!ipa.existsSync()) {
      throw const MacSigningException('installFailed', '待签名 IPA 不存在');
    }

    final work = await Directory.systemTemp.createTemp('duckmusic-sign-');
    try {
      final extracted = Directory('${work.path}/extracted');
      await extracted.create();
      final unpacked = await _run('/usr/bin/ditto', [
        '-x',
        '-k',
        ipa.path,
        extracted.path,
      ]);
      if (unpacked.exitCode != 0) {
        throw const MacSigningException('installFailed', 'IPA 解包失败');
      }
      final apps = extracted
          .listSync(recursive: true, followLinks: false)
          .whereType<Directory>()
          .where((directory) =>
              directory.path.endsWith('.app') &&
              directory.path.split(Platform.pathSeparator).contains('Payload'))
          .toList(growable: false);
      if (apps.length != 1) {
        throw const MacSigningException(
            'installFailed', 'IPA 中未找到唯一的 Payload 应用');
      }
      final appPath = apps.single.path;
      final infoPlist = File('$appPath/Info.plist');
      final bundleResult = await _run('/usr/bin/plutil', [
        '-extract',
        'CFBundleIdentifier',
        'raw',
        '-o',
        '-',
        infoPlist.path,
      ]);
      if (bundleResult.exitCode != 0 ||
          bundleResult.stdout.toString().trim() != bundleIdentifier) {
        throw const MacSigningException(
          'installFailed',
          'IPA 的 Bundle ID 与 DuckMusic 不匹配',
        );
      }
      final profilePlist = File('${work.path}/profile.plist');
      final decoded = await _run('/usr/bin/security', [
        'cms',
        '-D',
        '-i',
        context.profile.path,
        '-o',
        profilePlist.path,
      ]);
      if (decoded.exitCode != 0) {
        throw const MacSigningException('installFailed', '描述文件无法读取');
      }
      final entitlements = File('${work.path}/entitlements.plist');
      final extractedEntitlements = await _run('/usr/bin/plutil', [
        '-extract',
        'Entitlements',
        'xml1',
        '-o',
        entitlements.path,
        profilePlist.path,
      ]);
      if (extractedEntitlements.exitCode != 0) {
        throw const MacSigningException('installFailed', '描述文件缺少有效签名权限');
      }
      final embeddedProfile = File('$appPath/embedded.mobileprovision');
      await embeddedProfile
          .writeAsBytes(await File(context.profile.path).readAsBytes());

      for (final target in buildMacCodeSignPlan(appPath).takeWhile(
        (target) => target != appPath,
      )) {
        await _codesign(context.identity.label, target);
      }
      await _codesign(
        context.identity.label,
        appPath,
        entitlements: entitlements.path,
      );
      final verification = await _run('/usr/bin/codesign', [
        '--verify',
        '--deep',
        '--strict',
        appPath,
      ]);
      if (verification.exitCode != 0) {
        throw const MacSigningException('installFailed', '重签名校验失败');
      }
      final installResult = await _run('/usr/bin/xcrun', [
        'devicectl',
        'device',
        'install',
        'app',
        '--device',
        context.device.identifier,
        appPath,
      ]);
      if (installResult.exitCode != 0) {
        throw const MacSigningException(
            'installFailed', 'iPhone 安装失败，请检查信任和开发者模式');
      }
      return {
        'ok': true,
        'platform': 'macOS',
        'helperVersion': '0.2.0',
        'accountLabel': context.identity.label,
        'signatureExpiresAt':
            context.profile.expirationDate.toUtc().toIso8601String(),
        'devices': devices.map(_deviceToJson).toList(growable: false),
        'message': refreshing
            ? '已用本机当前有效描述文件重新签名并安装；描述文件到期前仍需再次生成或刷新'
            : '已完成本机重签名并安装到 iPhone',
      };
    } finally {
      if (await work.exists()) await work.delete(recursive: true);
    }
  }

  Future<void> _codesign(
    String identity,
    String target, {
    String? entitlements,
  }) async {
    final arguments = <String>[
      '--force',
      '--sign',
      identity,
      '--timestamp=none',
      if (entitlements != null) ...['--entitlements', entitlements],
      target,
    ];
    final result = await _run('/usr/bin/codesign', arguments);
    if (result.exitCode != 0) {
      throw const MacSigningException('installFailed', '代码签名失败');
    }
  }

  Future<List<MacIosDevice>> _listDevices() async {
    final directory =
        await Directory.systemTemp.createTemp('duckmusic-devices-');
    final output = File('${directory.path}/devices.json');
    try {
      final result = await _run('/usr/bin/xcrun', [
        'devicectl',
        'list',
        'devices',
        '--json-output',
        output.path,
        '--quiet',
      ]);
      if (result.exitCode != 0 || !output.existsSync()) return const [];
      return parseMacIosDevices(await output.readAsString());
    } finally {
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  }

  Future<List<MacProvisioningProfile>> _loadProfiles() async {
    final paths = <String>{};
    for (final directoryPath in [
      '$_homeDirectory/Library/Developer/Xcode/UserData/Provisioning Profiles',
      '$_homeDirectory/Library/MobileDevice/Provisioning Profiles',
    ]) {
      final directory = Directory(directoryPath);
      if (!directory.existsSync()) continue;
      for (final entity in directory.listSync(followLinks: false)) {
        if (entity is File && entity.path.endsWith('.mobileprovision')) {
          paths.add(entity.path);
        }
      }
    }
    final profiles = <MacProvisioningProfile>[];
    for (final path in paths) {
      try {
        final profile = await _decodeProfile(path);
        if (profile != null) profiles.add(profile);
      } on MacSigningException {
        // Ignore stale or unrelated profiles and keep looking for a match.
      }
    }
    return profiles;
  }

  Future<MacProvisioningProfile?> _decodeProfile(String path) async {
    final temporary =
        await Directory.systemTemp.createTemp('duckmusic-profile-');
    final plist = File('${temporary.path}/profile.plist');
    try {
      final decoded = await _run('/usr/bin/security', [
        'cms',
        '-D',
        '-i',
        path,
        '-o',
        plist.path,
      ]);
      if (decoded.exitCode != 0 || !plist.existsSync()) return null;
      final name = await _plutil(plist.path, 'Name');
      final uuid = await _plutil(plist.path, 'UUID');
      final expiration = await _plutil(plist.path, 'ExpirationDate');
      final appId =
          await _plutil(plist.path, 'Entitlements.application-identifier');
      final team = await _plutil(plist.path, 'TeamIdentifier.0');
      final devicesJson =
          await _plutil(plist.path, 'ProvisionedDevices', format: 'json');
      if (name == null ||
          uuid == null ||
          expiration == null ||
          appId == null ||
          team == null ||
          devicesJson == null) {
        return null;
      }
      final expirationDate = DateTime.tryParse(expiration)?.toUtc();
      final devices = jsonDecode(devicesJson);
      if (expirationDate == null || devices is! List) return null;
      final certificateSha1s = <String>[];
      for (var index = 0; index < 16; index++) {
        final certificate = await _plutil(
          plist.path,
          'DeveloperCertificates.$index',
        );
        if (certificate == null || certificate.trim().isEmpty) break;
        try {
          certificateSha1s.add(
            sha1
                .convert(base64Decode(certificate.trim()))
                .toString()
                .toUpperCase(),
          );
        } on FormatException {
          break;
        }
      }
      return MacProvisioningProfile(
        path: path,
        name: name,
        uuid: uuid,
        teamIdentifier: team,
        applicationIdentifier: appId,
        expirationDate: expirationDate,
        provisionedDevices: devices.whereType<String>().toList(growable: false),
        developerCertificateSha1s: certificateSha1s,
      );
    } finally {
      if (await temporary.exists()) await temporary.delete(recursive: true);
    }
  }

  Future<String?> _plutil(
    String path,
    String key, {
    String format = 'raw',
  }) async {
    final result = await _run('/usr/bin/plutil', [
      '-extract',
      key,
      format,
      '-o',
      '-',
      path,
    ]);
    return result.exitCode == 0 ? result.stdout.toString().trim() : null;
  }

  MacProvisioningProfile? _chooseProfileForStatus({
    required String bundleIdentifier,
    required List<MacSigningIdentity> identities,
    required List<MacProvisioningProfile> profiles,
  }) {
    final candidates = profiles
        .where(
          (profile) =>
              profile.bundleIdentifier == bundleIdentifier &&
              profile.expirationDate.isAfter(_now()) &&
              identities.any(
                (identity) =>
                    profile.developerCertificateSha1s.contains(identity.sha1),
              ),
        )
        .toList();
    candidates.sort(
      (left, right) => right.expirationDate.compareTo(left.expirationDate),
    );
    return candidates.firstOrNull;
  }

  Map<String, dynamic> _errorResponse({
    required String code,
    required String message,
  }) =>
      {
        'ok': false,
        'platform': 'macOS',
        'helperVersion': '0.2.0',
        'code': code,
        'message': message,
      };
}

Map<String, dynamic> _deviceToJson(MacIosDevice device) => {
      'name': device.name,
      'identifier': device.identifier,
      'udid': device.udid,
      'osVersion': device.osVersion,
      'connected': device.connected,
      'trusted': device.paired,
      'developerModeEnabled': device.developerModeEnabled,
    };

List<MacSigningIdentity> parseMacSigningIdentities(String output) {
  final pattern = RegExp(
    r'^\s*\d+\)\s+([0-9A-Fa-f]{40})\s+"([^"]+)"\s*$',
    multiLine: true,
  );
  return pattern
      .allMatches(output)
      .map(
        (match) => MacSigningIdentity(
          sha1: match.group(1)!.toUpperCase(),
          label: match.group(2)!,
        ),
      )
      .where((identity) => identity.label.startsWith('Apple Development:'))
      .toList(growable: false);
}

List<MacIosDevice> parseMacIosDevices(String json) {
  final decoded = jsonDecode(json);
  if (decoded is! Map) return const [];
  final result = decoded['result'];
  final rawDevices = result is Map ? result['devices'] : null;
  if (rawDevices is! List) return const [];

  final devices = <MacIosDevice>[];
  for (final raw in rawDevices) {
    if (raw is! Map) continue;
    final hardware = raw['hardwareProperties'];
    final properties = raw['deviceProperties'];
    final connection = raw['connectionProperties'];
    if (hardware is! Map ||
        properties is! Map ||
        hardware['platform'] != 'iOS' ||
        hardware['reality'] != 'physical') {
      continue;
    }
    final identifier = raw['identifier'];
    final udid = hardware['udid'];
    final name = properties['name'];
    if (identifier is! String || udid is! String || name is! String) continue;

    devices.add(
      MacIosDevice(
        identifier: identifier,
        udid: udid,
        name: name,
        connected:
            connection is Map && connection['tunnelState'] == 'connected',
        paired: connection is Map && connection['pairingState'] == 'paired',
        developerModeEnabled: properties['developerModeStatus'] == 'enabled',
        osVersion: properties['osVersionNumber'] as String?,
      ),
    );
  }
  return devices;
}

MacSigningContext selectMacSigningContext({
  required String bundleIdentifier,
  required List<MacSigningIdentity> identities,
  required List<MacProvisioningProfile> profiles,
  required List<MacIosDevice> devices,
  required DateTime now,
}) {
  if (identities.isEmpty) {
    throw const MacSigningException(
      'helperMissing',
      '未找到可用的 Apple Development 签名证书',
    );
  }

  final connectedDevices = devices
      .where((device) => device.connected && device.paired)
      .toList(growable: false);
  if (connectedDevices.isEmpty) {
    throw const MacSigningException('appleDevicesMissing', '未找到已连接并配对的 iPhone');
  }
  final developerModeDevice = connectedDevices
      .where((device) => device.developerModeEnabled)
      .firstOrNull;
  if (developerModeDevice == null) {
    throw const MacSigningException(
      'developerModeRequired',
      '请在 iPhone 上开启开发者模式',
    );
  }

  final candidates = <MacSigningContext>[];
  for (final profile in profiles) {
    if (profile.bundleIdentifier != bundleIdentifier ||
        !profile.expirationDate.isAfter(now) ||
        !profile.provisionedDevices.contains(developerModeDevice.udid)) {
      continue;
    }
    for (final identity in identities) {
      if (profile.developerCertificateSha1s.contains(identity.sha1)) {
        candidates.add(
          MacSigningContext(
            identity: identity,
            profile: profile,
            device: developerModeDevice,
          ),
        );
      }
    }
  }
  if (candidates.isEmpty) {
    throw const MacSigningException(
      'profileExpired',
      '未找到同时匹配 DuckMusic、当前证书和已连接设备的有效描述文件',
    );
  }
  candidates.sort(
    (left, right) =>
        right.profile.expirationDate.compareTo(left.profile.expirationDate),
  );
  return candidates.first;
}

List<String> buildMacCodeSignPlan(String appPath) {
  final app = Directory(appPath);
  if (!app.existsSync()) {
    throw const MacSigningException('installFailed', 'IPA 中缺少应用包');
  }

  final nestedApps = app
      .listSync(recursive: true, followLinks: false)
      .whereType<Directory>()
      .where(
        (directory) =>
            directory.path.endsWith('.appex') ||
            directory.path.endsWith('.app') ||
            directory.path.contains(
                '${Platform.pathSeparator}Watch${Platform.pathSeparator}') ||
            directory.path.contains(
              '${Platform.pathSeparator}AppClips${Platform.pathSeparator}',
            ),
      )
      .toList(growable: false);
  if (nestedApps.isNotEmpty) {
    throw const MacSigningException(
      'installFailed',
      '当前版本暂不支持包含 App Extension、Watch App 或 App Clip 的 IPA',
    );
  }

  final nestedCode = app
      .listSync(recursive: true, followLinks: false)
      .where(
        (entity) =>
            entity is Directory && entity.path.endsWith('.framework') ||
            entity is File && entity.path.endsWith('.dylib'),
      )
      .map((entity) => entity.path)
      .toList();
  nestedCode.sort((left, right) {
    final depth = _pathDepth(right).compareTo(_pathDepth(left));
    return depth == 0 ? left.compareTo(right) : depth;
  });
  return [...nestedCode, app.path];
}

int _pathDepth(String path) => Platform.pathSeparator.allMatches(path).length;

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
