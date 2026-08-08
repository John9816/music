# DuckMusic Desktop iOS Sideload Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a macOS/Windows-only iOS Install Center that reads a verified ECS manifest, reports local signing prerequisites, and invokes a local signer without sending Apple credentials to ECS.

**Architecture:** Keep ECS access and task state in Dart. Use a bundled local Helper process behind the existing adapter interface for signing/install operations. macOS performs real local IPA signing with the user's existing Apple Development identity/profile and `devicectl`; Windows remains diagnostic-only until a separately audited local signing service is selected.

**Tech Stack:** Flutter/Dart, `http`, `crypto`, `provider`, Flutter platform channels, macOS/Windows desktop process discovery, `flutter_test`.

---

### Task 1: Define manifest, device, and task models

**Files:**
- Create: `lib/core/models/ios_sideload.dart`
- Test: `test/ios_sideload_models_test.dart`

- [x] **Step 1: Write failing model tests**

Test JSON parsing for a valid manifest, rejection of missing/invalid SHA-256, and the refresh threshold calculation for a seven-day profile.

- [x] **Step 2: Run the focused test**

Run: `flutter test test/ios_sideload_models_test.dart`

Expected: FAIL because the model types do not exist.

- [x] **Step 3: Implement immutable model types**

Create `IosSideloadManifest`, `IosSideloadDevice`, `IosSideloadStatus`, `IosSideloadTaskState`, and `IosSideloadErrorCode`. Validate required fields and expose `needsRefresh(now)` with a 24-hour threshold.

- [x] **Step 4: Run the focused test again**

Run: `flutter test test/ios_sideload_models_test.dart`

Expected: PASS.

### Task 2: Implement ECS manifest and local adapter service

**Files:**
- Create: `lib/core/services/ios_sideload_service.dart`
- Modify: `lib/core/config/app_config.dart`
- Modify: `pubspec.yaml`
- Test: `test/ios_sideload_service_test.dart`

- [x] **Step 1: Write failing service tests**

Cover manifest fetch and hash validation, disabled configuration, concurrent task rejection, and conversion of missing local helper/device errors into structured status.

- [x] **Step 2: Run the focused test**

Run: `flutter test test/ios_sideload_service_test.dart`

Expected: FAIL because the service does not exist.

- [x] **Step 3: Add the direct hashing dependency**

Add `crypto: ^3.0.7` to `pubspec.yaml` so the service can verify SHA-256 with `sha256.convert(bytes)` rather than relying on an ad-hoc implementation.

- [x] **Step 4: Implement the service**

Add an injectable `http.Client`, manifest URL from `IOS_SIDELOAD_MANIFEST_URL`, SHA-256 verification using `sha256.convert(bytes)`, and a `MethodChannel('com.duckmusic.ios_sideload')` adapter. The service must expose `loadManifest`, `refreshStatus`, `installLatest`, `refreshInstalled`, and `cancel`, and serialize operations so only one install/refresh task runs at a time.

- [x] **Step 5: Run focused tests**

Run: `flutter test test/ios_sideload_service_test.dart`

Expected: PASS.

### Task 3: Add the desktop iOS Install Center UI

**Files:**
- Create: `lib/features/settings/ios_sideload_view.dart`
- Modify: `lib/features/settings/settings_view.dart`
- Modify: `lib/app.dart`
- Test: `test/ios_sideload_view_test.dart`

- [x] **Step 1: Write failing widget tests**

Verify the row is desktop-only, the page shows “not configured” when the manifest URL is empty, shows the verified version when a manifest is loaded, disables duplicate install actions, and renders actionable diagnostics for missing helpers/devices.

- [x] **Step 2: Run the focused widget test**

Run: `flutter test test/ios_sideload_view_test.dart`

Expected: FAIL because the view and provider wiring do not exist.

- [x] **Step 3: Implement provider wiring and UI**

Register `IosSideloadService` in `MultiProvider`, add a desktop-only “iOS 安装中心” settings row, and implement a compact status page with latest build, device state, signature expiry, install/refresh buttons, and a diagnostics section. Do not display Apple ID password inputs or imply that a refresh succeeded without adapter confirmation.

- [x] **Step 4: Run focused widget tests**

Run: `flutter test test/ios_sideload_view_test.dart`

Expected: PASS.

### Task 4: Add platform diagnostics and packaging documentation

**Files:**
- Modify: `README.md`
- Modify: `RELEASE.md`

- [x] **Step 1: Document the DMG/EXE user flow**

Document that users install the desktop package, configure their own local Apple signing helper, connect a trusted device, and keep the helper running for pre-expiry refresh. State that ECS never receives Apple credentials and that free personal provisioning retains Apple’s validity and device limits.

- [x] **Step 2: Run platform-aware static checks**

Run: `flutter analyze`

Expected: no new analyzer errors. On non-macOS/non-Windows hosts, platform handlers remain compilable through guarded code paths.

### Task 5: Full verification

**Files:**
- No new files.

- [x] **Step 1: Run all Dart tests**

Run: `flutter test`

Expected: all tests pass.

- [x] **Step 2: Run analyzer and desktop build checks**

Run: `flutter analyze` and, where the host toolchain exists, `flutter build macos --debug` or `flutter build windows --debug`.

Expected: analyzer exits 0; unavailable platform toolchains are reported as environment limitations rather than hidden.

- [x] **Step 3: Review the diff**

Run: `git diff --check` and `git status --short`.

Expected: no whitespace errors, and only intended feature files are changed in addition to pre-existing worktree changes.
