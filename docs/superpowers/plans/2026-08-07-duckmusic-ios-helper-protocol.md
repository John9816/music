# DuckMusic iOS Helper Protocol Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the placeholder platform channel with a cross-platform local helper process that receives a verified temporary IPA and returns structured signing/device diagnostics without exposing Apple credentials.

**Architecture:** Flutter owns ECS download, SHA-256 verification, task serialization, and temporary-file cleanup. A bundled `duckmusic-ios-helper` process owns local device/signing prerequisites and communicates through one JSON object on stdout. The initial helper implements truthful diagnostics and explicit unsupported errors; signing code can be added behind the stable protocol without changing the Flutter UI.

**Tech Stack:** Flutter/Dart, `dart:io`, JSON process protocol, Xcode `devicectl` diagnostics on macOS, Windows service/driver diagnostics, `flutter_test`.

---

### Task 1: Verify temporary IPA handoff

**Files:**
- Modify: `lib/core/services/ios_sideload_service.dart`
- Modify: `test/ios_sideload_service_test.dart`

- [x] Write a failing test that asserts the adapter receives an existing IPA path whose bytes match the verified ECS download, and that the temporary directory is removed after completion.
- [x] Change `IosSideloadPlatformAdapter.install/refresh` to accept `ipaPath` and return `IosSideloadStatus`.
- [x] Write verified bytes to a random system temporary directory, invoke the adapter, and delete the directory in `finally`.
- [x] Run `flutter test test/ios_sideload_service_test.dart` and require all service tests to pass.

### Task 2: Implement the helper process adapter

**Files:**
- Modify: `lib/core/config/app_config.dart`
- Modify: `lib/core/services/ios_sideload_service.dart`
- Create: `test/ios_sideload_process_adapter_test.dart`

- [x] Write failing tests for helper discovery, JSON status parsing, structured error parsing, install arguments, and cancellation.
- [x] Add `IOS_SIDELOAD_HELPER_PATH` and `DUCKMUSIC_IOS_HELPER` discovery, then packaged-resource fallbacks for macOS and Windows.
- [x] Implement `ProcessIosSideloadAdapter` with a cancellable injected command runner. Never place Apple ID, password, session tokens, profiles, or private keys in process arguments.
- [x] Make the process adapter the production default while retaining `MethodChannelIosSideloadAdapter` as a compatibility adapter.
- [x] Run `flutter test test/ios_sideload_process_adapter_test.dart test/ios_sideload_service_test.dart`.

### Task 3: Add the diagnostic helper CLI

**Files:**
- Create: `tool/duckmusic_ios_helper.dart`
- Create: `test/ios_sideload_helper_cli_test.dart`

- [x] Write failing tests for stable JSON status output and explicit `helperMissing` responses for install/refresh when no signing backend is configured.
- [x] Implement macOS checks for Xcode command-line tools and `xcrun devicectl` devices without reading Apple credentials.
- [x] Implement macOS local IPA signing with `security`, `plutil`, `codesign`, and `xcrun devicectl`; select only matching Apple Development identity/profile/device tuples.
- [x] Verify one locally generated IPA installs on a paired iPhone and read back the installed bundle from `devicectl`.
- [ ] Implement Windows checks for Apple Mobile Device and Bonjour services using `sc query`, with structured missing-component diagnostics.
- [x] Ensure stdout contains only JSON and diagnostics go to stderr.
- [x] Run `flutter test test/ios_sideload_helper_cli_test.dart`.

### Task 4: Package helper artifacts

**Files:**
- Create: `scripts/build_ios_helper.sh`
- Create: `scripts/build_ios_helper.ps1`
- Modify: `.github/workflows/flutter-release.yml`
- Modify: `README.md`
- Modify: `RELEASE.md`

- [x] Compile `tool/duckmusic_ios_helper.dart` to a native executable before macOS/Windows packaging.
- [x] Place the macOS helper in `7511.app/Contents/Resources/duckmusic-ios-helper` before signing/notarization.
- [x] Place the Windows helper beside `duck_music.exe` and include it in the Inno Setup installer.
- [x] Document the helper protocol, macOS signing backend, Windows diagnostic-only state, and required ECS public manifest.

### Task 5: Verify

**Files:**
- No new files.

- [x] Run `dart format` on new Dart files.
- [x] Run the full `flutter test` suite and require all tests to pass.
- [x] Run `flutter analyze` and require no issues.
- [x] Run `flutter build macos --debug` and compile the local helper executable.
- [x] Run `git diff --check`; report that Windows compilation requires a Windows runner.
