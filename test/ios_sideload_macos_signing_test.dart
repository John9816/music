import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/ios_sideload/macos_signing.dart';

void main() {
  test('parses only valid Apple Development signing identities', () {
    const output = '''
  1) C31A85ED0BC364441EB069D191357D6BF18EF27E "Apple Development: user@example.com (8466RG5RU9)"
  2) 1111111111111111111111111111111111111111 "Developer ID Application: Example"
     2 valid identities found
''';

    expect(
      parseMacSigningIdentities(output),
      const [
        MacSigningIdentity(
          sha1: 'C31A85ED0BC364441EB069D191357D6BF18EF27E',
          label: 'Apple Development: user@example.com (8466RG5RU9)',
        ),
      ],
    );
  });

  test('parses physical iOS devices from devicectl JSON', () {
    final devices = parseMacIosDevices(jsonEncode({
      'result': {
        'devices': [
          {
            'identifier': 'core-device-id',
            'visibilityClass': 'default',
            'connectionProperties': {
              'pairingState': 'paired',
              'tunnelState': 'connected',
            },
            'deviceProperties': {
              'name': 'iPhone',
              'osVersionNumber': '17.7',
              'developerModeStatus': 'enabled',
            },
            'hardwareProperties': {
              'platform': 'iOS',
              'reality': 'physical',
              'udid': '00008120-00084CCA210BC01E',
            },
          },
          {
            'identifier': 'simulator-id',
            'deviceProperties': {'name': 'Simulator'},
            'hardwareProperties': {
              'platform': 'iOS',
              'reality': 'simulated',
              'udid': 'simulator-udid',
            },
          },
        ],
      },
    }));

    expect(devices, hasLength(1));
    expect(devices.single.identifier, 'core-device-id');
    expect(devices.single.udid, '00008120-00084CCA210BC01E');
    expect(devices.single.connected, isTrue);
    expect(devices.single.paired, isTrue);
    expect(devices.single.developerModeEnabled, isTrue);
    expect(devices.single.osVersion, '17.7');
  });

  test('selects a profile matching bundle, device, and signing certificate',
      () {
    const identity = MacSigningIdentity(
      sha1: 'C31A85ED0BC364441EB069D191357D6BF18EF27E9',
      label: 'Apple Development: user@example.com (8466RG5RU9)',
    );
    final matchingProfile = MacProvisioningProfile(
      path: '/profiles/matching.mobileprovision',
      name: 'DuckMusic development',
      uuid: 'profile-1',
      teamIdentifier: 'N8Y55G4BTY',
      applicationIdentifier: 'N8Y55G4BTY.com.751152.duckMusic',
      expirationDate: DateTime.utc(2026, 8, 11),
      provisionedDevices: const ['device-udid'],
      developerCertificateSha1s: const [
        'C31A85ED0BC364441EB069D191357D6BF18EF27E9',
      ],
    );
    const device = MacIosDevice(
      identifier: 'core-device-id',
      udid: 'device-udid',
      name: 'iPhone',
      connected: true,
      paired: true,
      developerModeEnabled: true,
    );

    final context = selectMacSigningContext(
      bundleIdentifier: 'com.751152.duckMusic',
      identities: const [identity],
      profiles: [
        MacProvisioningProfile(
          path: '/profiles/wrong.mobileprovision',
          name: 'Wrong app',
          uuid: 'profile-2',
          teamIdentifier: 'N8Y55G4BTY',
          applicationIdentifier: 'N8Y55G4BTY.com.example.other',
          expirationDate: DateTime.utc(2026, 8, 20),
          provisionedDevices: const ['device-udid'],
          developerCertificateSha1s: const [
            'C31A85ED0BC364441EB069D191357D6BF18EF27E',
          ],
        ),
        matchingProfile,
      ],
      devices: const [device],
      now: DateTime.utc(2026, 8, 7),
    );

    expect(context.identity, identity);
    expect(context.profile, matchingProfile);
    expect(context.device, device);
  });

  test('rejects a profile that does not include a connected device', () {
    expect(
      () => selectMacSigningContext(
        bundleIdentifier: 'com.751152.duckMusic',
        identities: const [
          MacSigningIdentity(
            sha1: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
            label: 'Apple Development: user@example.com (TEAM)',
          ),
        ],
        profiles: [
          MacProvisioningProfile(
            path: '/profiles/profile.mobileprovision',
            name: 'DuckMusic development',
            uuid: 'profile-1',
            teamIdentifier: 'TEAM',
            applicationIdentifier: 'TEAM.com.751152.duckMusic',
            expirationDate: DateTime.utc(2026, 8, 11),
            provisionedDevices: const ['different-device'],
            developerCertificateSha1s: const [
              'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
            ],
          ),
        ],
        devices: const [
          MacIosDevice(
            identifier: 'core-device-id',
            udid: 'device-udid',
            name: 'iPhone',
            connected: true,
            paired: true,
            developerModeEnabled: true,
          ),
        ],
        now: DateTime.utc(2026, 8, 7),
      ),
      throwsA(
        isA<MacSigningException>().having(
          (error) => error.code,
          'code',
          'profileExpired',
        ),
      ),
    );
  });

  test('builds a deepest-first signing plan and rejects app extensions', () {
    final temporary = Directory.systemTemp.createTempSync('duckmusic-plan-');
    addTearDown(() => temporary.deleteSync(recursive: true));
    final app = Directory('${temporary.path}/DuckMusic.app')..createSync();
    Directory('${app.path}/Frameworks/Alpha.framework')
        .createSync(recursive: true);
    Directory(
            '${app.path}/Frameworks/Alpha.framework/Frameworks/Beta.framework')
        .createSync(recursive: true);
    File('${app.path}/Frameworks/libswiftCore.dylib')
        .createSync(recursive: true);

    final plan = buildMacCodeSignPlan(app.path);

    expect(plan.last, app.path);
    expect(
      plan.indexOf(
        '${app.path}/Frameworks/Alpha.framework/Frameworks/Beta.framework',
      ),
      lessThan(plan.indexOf('${app.path}/Frameworks/Alpha.framework')),
    );

    Directory('${app.path}/PlugIns/Share.appex').createSync(recursive: true);
    expect(
      () => buildMacCodeSignPlan(app.path),
      throwsA(
        isA<MacSigningException>().having(
          (error) => error.code,
          'code',
          'installFailed',
        ),
      ),
    );
  });
}
