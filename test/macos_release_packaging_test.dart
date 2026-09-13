import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  if (Platform.isWindows) {
    test('macOS packaging requires a POSIX host', () {},
        skip: 'Run these script tests on macOS or Linux.');
    return;
  }
  late _PackagingFixture fixture;

  setUp(() async {
    fixture = await _PackagingFixture.create();
  });

  tearDown(() {
    fixture.root.deleteSync(recursive: true);
  });

  test('release rejects absent credentials before creating a package',
      () async {
    final result = await fixture.package(mode: 'release');
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('MACOS_SIGNING_IDENTITY'));
    expect(fixture.artifacts, isEmpty);
    expect(fixture.commands, isEmpty);
  });

  test('release refuses ad-hoc and Apple Development identities', () async {
    for (final identity in ['-', 'Apple Development: Example (ABCDEFGHIJ)']) {
      final result = await fixture.package(
        mode: 'release',
        environment: {
          ...fixture.releaseEnvironment,
          'MACOS_SIGNING_IDENTITY': identity,
        },
      );
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('Developer ID Application'));
      expect(fixture.artifacts, isEmpty);
    }
  });

  test('missing helper cannot be sealed into a distributable app', () async {
    fixture.helper.deleteSync();
    final result = await fixture.package();
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('helper'));
    expect(fixture.artifacts, isEmpty);
    expect(fixture.commands.where((line) => line.startsWith('codesign ')),
        isEmpty);
  });

  test('wrong helper architecture prevents signing and publication', () async {
    fixture.helper.writeAsStringSync('MACHO x86_64\n');
    final result = await fixture.package();
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('arm64'));
    expect(fixture.artifacts, isEmpty);
    expect(fixture.commands.where((line) => line.startsWith('codesign ')),
        isEmpty);
  });

  test('an incompatible embedded framework prevents publication', () async {
    fixture.frameworkBinary.writeAsStringSync('MACHO x86_64\n');
    final result = await fixture.package();
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('Plugin'));
    expect(fixture.artifacts, isEmpty);
  });

  test('a mismatched bundle version prevents publication', () async {
    fixture.writePlist(version: '1.2.2');
    final result = await fixture.package();
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('version'));
    expect(fixture.artifacts, isEmpty);
  });

  test('native layout check accepts the host Mach-O architecture', () async {
    final host = await Process.run('uname', ['-m']);
    final arch = host.stdout.toString().trim() == 'arm64' ? 'arm64' : 'x64';
    for (final path in [
      '${fixture.app.path}/Contents/MacOS/7511',
      fixture.helper.path,
      fixture.frameworkBinary.path,
    ]) {
      File(Platform.resolvedExecutable).copySync(path);
    }
    final result = await Process.run('bash', [
      'scripts/verify_macos_app.sh',
      fixture.app.path,
      arch,
      '1.2.3',
      '42',
      'layout',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  }, skip: !Platform.isMacOS);

  test('Dart helper can execute with its hardened runtime entitlements',
      () async {
    final binary = '${fixture.root.path}/native-helper';
    final build =
        await Process.run('bash', ['scripts/build_ios_helper.sh', binary]);
    expect(build.exitCode, 0, reason: '${build.stdout}\n${build.stderr}');
    final sign = await Process.run('codesign', [
      '--force',
      '--options',
      'runtime',
      '--timestamp=none',
      '--sign',
      '-',
      '--entitlements',
      'macos/Runner/Helper.entitlements',
      binary,
    ]);
    expect(sign.exitCode, 0, reason: '${sign.stdout}\n${sign.stderr}');
    final response =
        await Process.run(binary, ['audit-unknown-command', '--json']);
    expect(response.exitCode, 2,
        reason: 'The helper must respond instead of being killed by macOS.');
    expect(jsonDecode(response.stdout.toString()),
        containsPair('code', 'unknown'));
  }, skip: !Platform.isMacOS, timeout: const Timeout(Duration(seconds: 90)));

  test('development package signs helper before app and verifies mounted copy',
      () async {
    final result = await fixture.package();
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(fixture.artifacts.map((file) => file.uri.pathSegments.last), [
      'DuckMusic-Flutter-v1.2.3-macOS-arm64-development.dmg',
    ]);
    final signatures = fixture.commands
        .where(
            (line) => line.startsWith('codesign ') && line.contains('--sign'))
        .toList();
    final helperIndex =
        signatures.indexWhere((line) => line.endsWith('duckmusic-ios-helper'));
    final outerIndex =
        signatures.indexWhere((line) => line.endsWith('/7511.app'));
    expect(helperIndex, greaterThanOrEqualTo(0));
    expect(outerIndex, greaterThan(helperIndex));
    expect(signatures[helperIndex], contains('Helper.entitlements'));
    expect(signatures[outerIndex], contains('Release.entitlements'));
    expect(
        fixture.commands.any((line) => line.contains('notarytool')), isFalse);
    expect(
      fixture.commands.any((line) =>
          line.startsWith('codesign --verify') &&
          line.contains('/mount/7511.app')),
      isTrue,
    );
    expect(fixture.commands.any((line) => line.startsWith('hdiutil detach')),
        isTrue);
    expect(fixture.helper.readAsStringSync(), 'MACHO arm64\n');
  });

  test('a failed signature check never produces a DMG', () async {
    final result = await fixture.package(environment: {'FAIL_VERIFY': 'all'});
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('sealed resource'));
    expect(fixture.artifacts, isEmpty);
    expect(fixture.commands.any((line) => line.startsWith('hdiutil create')),
        isFalse);
  });

  test('mounted contents are checked and detached on validation failure',
      () async {
    final result =
        await fixture.package(environment: {'FAIL_VERIFY': 'mounted'});
    expect(result.exitCode, isNot(0));
    expect(fixture.artifacts, isEmpty);
    expect(fixture.commands.any((line) => line.startsWith('hdiutil detach')),
        isTrue);
  });

  test('Apple Invalid status is rejected even when notarytool exits zero',
      () async {
    final result = await fixture.package(
      mode: 'release',
      environment: {
        ...fixture.releaseEnvironment,
        'NOTARY_STATUS': 'Invalid',
      },
    );
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('Accepted'));
    expect(result.stderr, contains('12345678-1234-1234-1234-123456789abc'));
    expect(result.stderr, contains('The signature is invalid.'));
    expect(fixture.artifacts, isEmpty);
    expect(fixture.commands.any((line) => line.startsWith('hdiutil create')),
        isFalse);
  });

  test('notarytool nonzero exit retains submission ID and safe diagnostics',
      () async {
    final result = await fixture.package(
      mode: 'release',
      environment: {
        ...fixture.releaseEnvironment,
        'NOTARY_EXIT': '69',
        'NOTARY_STATUS': 'In Progress',
      },
    );
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('command_exit=69'));
    expect(result.stderr, contains('12345678-1234-1234-1234-123456789abc'));
    expect(result.stderr, contains('The signature is invalid.'));
    expect(fixture.artifacts, isEmpty);
  });

  test('release publishes only after app and DMG notarization and assessment',
      () async {
    final result = await fixture.package(
      mode: 'release',
      environment: fixture.releaseEnvironment,
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(fixture.artifacts.map((file) => file.uri.pathSegments.last), [
      'DuckMusic-Flutter-v1.2.3-macOS-arm64.dmg',
    ]);
    expect(
      fixture.commands.where((line) => line.contains('notarytool submit')),
      hasLength(2),
    );
    expect(
      fixture.commands.any(
          (line) => line.startsWith('spctl ') && line.contains('--type open')),
      isTrue,
    );
    expect(
      fixture.commands.any((line) =>
          line.contains('stapler validate') &&
          line.contains('/mount/7511.app')),
      isTrue,
    );
  });

  test('a failed Gatekeeper assessment prevents release output', () async {
    final result = await fixture.package(
      mode: 'release',
      environment: {...fixture.releaseEnvironment, 'FAIL_ASSESS': '1'},
    );
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('Gatekeeper'));
    expect(fixture.artifacts, isEmpty);
  });

  test('signing setup fails closed without printing credential values',
      () async {
    final result = await Process.run(
      'bash',
      ['scripts/configure_macos_signing.sh'],
      environment: {
        'PATH': Platform.environment['PATH']!,
        'MACOS_CERTIFICATE_BASE64': 'do-not-print-this-value',
      },
      includeParentEnvironment: false,
    );
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('MACOS_CERTIFICATE_PASSWORD'));
    expect('${result.stdout}${result.stderr}',
        isNot(contains('do-not-print-this-value')));
  });
}

class _PackagingFixture {
  _PackagingFixture(this.root);

  final Directory root;
  Directory get app => Directory('${root.path}/7511.app');
  File get helper =>
      File('${app.path}/Contents/Resources/duckmusic-ios-helper');
  File get frameworkBinary => File(
      '${app.path}/Contents/Frameworks/Plugin.framework/Versions/A/Plugin');
  File get log => File('${root.path}/commands.log');
  List<String> get commands => log.existsSync() ? log.readAsLinesSync() : [];
  List<FileSystemEntity> get artifacts {
    final output = Directory('${root.path}/dist');
    return output.existsSync() ? output.listSync() : [];
  }

  Map<String, String> get releaseEnvironment => {
        'MACOS_SIGNING_IDENTITY':
            'Developer ID Application: Example (ABCDEFGHIJ)',
        'APPLE_TEAM_ID': 'ABCDEFGHIJ',
        'MACOS_KEYCHAIN': '${root.path}/signing.keychain-db',
        'MACOS_NOTARIZATION_PROFILE': 'duckmusic-test',
        'STUB_RELEASE': '1',
      };

  static Future<_PackagingFixture> create() async {
    final root = Directory.systemTemp.createTempSync('duckmusic-macos-test.');
    final fixture = _PackagingFixture(root);
    Directory('${root.path}/bin').createSync();
    Directory('${root.path}/work').createSync();
    Directory('${root.path}/state').createSync();
    File('${root.path}/signing.keychain-db').writeAsStringSync('fixture');
    for (final file in [
      File('${fixture.app.path}/Contents/MacOS/7511'),
      fixture.helper,
      fixture.frameworkBinary,
    ]) {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('MACHO x86_64 arm64\n');
      await Process.run('chmod', ['755', file.path]);
    }
    // The helper is compiled on the target runner, while Flutter can be universal.
    fixture.helper.writeAsStringSync('MACHO arm64\n');
    fixture.writePlist();
    for (final tool in [
      'codesign',
      'file',
      'lipo',
      'plutil',
      'ditto',
      'hdiutil',
      'xcrun',
      'spctl',
    ]) {
      final executable = File('${root.path}/bin/$tool');
      executable.writeAsStringSync(_controlledTools);
      await Process.run('chmod', ['755', executable.path]);
    }
    return fixture;
  }

  void writePlist({String version = '1.2.3'}) {
    File('${app.path}/Contents/Info.plist').writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key>
<string>com.751152.duckMusic</string>
<key>CFBundleExecutable</key>
<string>7511</string>
<key>CFBundleShortVersionString</key>
<string>$version</string>
<key>CFBundleVersion</key>
<string>42</string>
</dict></plist>
''');
  }

  Future<ProcessResult> package({
    String mode = 'development',
    Map<String, String> environment = const {},
  }) =>
      Process.run(
        'bash',
        [
          'scripts/package_macos.sh',
          app.path,
          'arm64',
          '1.2.3',
          '42',
          '${root.path}/dist',
          mode,
        ],
        environment: {
          'PATH': '${root.path}/bin:${Platform.environment['PATH']}',
          'TMPDIR': '${root.path}/work',
          'TOOL_LOG': log.path,
          'STUB_STATE': '${root.path}/state',
          ...environment,
        },
        includeParentEnvironment: false,
      );
}

// The real packaging scripts run unchanged. Only macOS and Apple service
// boundaries are replaced, so these tests also run on the Linux validate job.
const _controlledTools = r'''#!/usr/bin/env bash
set -euo pipefail
tool="${0##*/}"
target="${@: -1}"
case "$tool" in
  file)
    if [[ "$(head -n1 "$target")" == MACHO* ]]; then
      echo 'Mach-O 64-bit executable'
    else
      echo 'data'
    fi
    ;;
  lipo)
    [[ "$2" == '-verify_arch' ]]
    grep -qw -- "$3" "$1"
    ;;
  plutil)
    key="$2"
    if [[ "$target" == *.json ]]; then
      if [[ "$key" == issues ]]; then
        sed -nE 's/[[:space:]]*"issues":(.*)/\1/p' "$target"
      else
        sed -nE "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]+)\".*/\1/p" "$target"
      fi
    else
      awk -v key="$key" '$0 ~ "<key>" key "</key>" {getline; sub(/^.*<string>/, ""); sub(/<\/string>.*$/, ""); print; found=1} END {if (!found) exit 1}' "$target"
    fi
    ;;
  codesign)
    printf '%s\n' "codesign $*" >> "$TOOL_LOG"
    if [[ "$1" == '--display' ]]; then
      printf '%s\n' 'CodeDirectory v=20500 flags=0x10000(runtime)' \
        'Authority=Developer ID Application: Example (ABCDEFGHIJ)' \
        'TeamIdentifier=ABCDEFGHIJ' 'Timestamp=Sep 13, 2026 at 12:00:00 PM'
    elif [[ "$1" == '--verify' ]]; then
      if [[ "${FAIL_VERIFY:-}" == 'all' ||
            ( "${FAIL_VERIFY:-}" == 'mounted' && "$target" == */mount/* ) ]]; then
        echo 'a sealed resource is missing or invalid' >&2
        exit 1
      fi
    fi
    ;;
  ditto)
    if [[ "$1" == '-c' ]]; then
      touch "$target"
    else
      cp -R "$1" "$2"
    fi
    ;;
  hdiutil)
    printf '%s\n' "hdiutil $*" >> "$TOOL_LOG"
    case "$1" in
      create)
        for ((i=1; i<=$#; i++)); do
          if [[ "${!i}" == '-srcfolder' ]]; then
            next=$((i+1))
            printf '%s' "${!next}" > "$STUB_STATE/dmg-source"
          fi
        done
        printf 'fixture DMG\n' > "$target"
        ;;
      attach)
        for ((i=1; i<=$#; i++)); do
          if [[ "${!i}" == '-mountpoint' ]]; then
            next=$((i+1))
            mountpoint="${!next}"
          fi
        done
        cp -R "$(< "$STUB_STATE/dmg-source")/." "$mountpoint"
        ;;
    esac
    ;;
  xcrun)
    printf '%s\n' "xcrun $*" >> "$TOOL_LOG"
    if [[ "$1 $2" == 'notarytool submit' ]]; then
      printf '{"id":"12345678-1234-1234-1234-123456789abc","status":"%s"}\n' "${NOTARY_STATUS:-Accepted}"
      exit "${NOTARY_EXIT:-0}"
    elif [[ "$1 $2" == 'notarytool log' ]]; then
      printf '%s\n' '{' \
        '"statusSummary":"Archive contains critical validation errors",' \
        '"issues":[{"severity":"error","message":"The signature is invalid."}]' \
        '}' > "$target"
    fi
    ;;
  spctl)
    printf '%s\n' "spctl $*" >> "$TOOL_LOG"
    if [[ "${FAIL_ASSESS:-0}" == '1' ]]; then
      echo 'Gatekeeper rejected fixture' >&2
      exit 1
    fi
    ;;
esac
''';
