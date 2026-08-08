# Android Playlist Management Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship an Android-only DuckMusic update with playlist deletion, a single toolbox live-TV entry, and reliable cross-source playback clocks.

**Architecture:** Reuse the backend's existing single-delete endpoints and compose batch operations in the Flutter client. Keep deletion policy in `UserApi`, selection state in the two playlist views, navigation ownership in `HomeShell`, and platform audio-header policy in a small pure helper that can be unit tested.

**Tech Stack:** Flutter/Dart, Provider, just_audio, flutter_test, GitHub Actions, ECS update manifest.

---

### Task 1: Native audio-header delivery

**Files:**
- Create: `lib/core/player/audio_source_policy.dart`
- Modify: `lib/core/player/player_controller.dart`
- Test: `test/player_controller_test.dart`

- [ ] **Step 1: Write the failing platform-policy test**

```dart
test('mobile and Darwin players deliver audio headers natively', () {
  expect(usesNativeAudioHeaders(TargetPlatform.android), isTrue);
  expect(usesNativeAudioHeaders(TargetPlatform.iOS), isTrue);
  expect(usesNativeAudioHeaders(TargetPlatform.macOS), isTrue);
  expect(usesNativeAudioHeaders(TargetPlatform.windows), isFalse);
});
```

- [ ] **Step 2: Run the test and verify RED**

Run: `flutter test test/player_controller_test.dart`
Expected: compilation fails because `usesNativeAudioHeaders` does not exist.

- [ ] **Step 3: Add the pure policy and configure AudioPlayer**

```dart
bool usesNativeAudioHeaders(TargetPlatform platform) => switch (platform) {
  TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.macOS => true,
  _ => false,
};
```

Initialize `AudioPlayer` with
`useProxyForRequestHeaders: !usesNativeAudioHeaders(defaultTargetPlatform)`.
Keep the existing source-aware `LockCachingAudioSource` condition.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run: `flutter test test/player_controller_test.dart test/settings_and_cache_test.dart`
Expected: all tests pass.

### Task 2: Playlist deletion API surface

**Files:**
- Modify: `lib/core/api/user_api.dart`
- Test: `test/api_client_test.dart`

- [ ] **Step 1: Write failing request-path tests**

Cover these exact operations with the existing local HTTP test server:

```dart
await api.deleteUserPlaylist('42', token);
await api.deleteUserPlaylistSong('42', '9', token);
```

Assert DELETE paths `/api/user/music/playlists/42` and
`/api/user/music/playlists/42/items/9`, including the bearer token.

- [ ] **Step 2: Run the API tests and verify RED**

Run: `flutter test test/api_client_test.dart`
Expected: compilation fails because both methods are missing.

- [ ] **Step 3: Implement the two UserApi methods**

```dart
Future<void> deleteUserPlaylist(String playlistId, String token) async {
  await _client.deleteJson(
    'api/user/music/playlists/${Uri.encodeComponent(playlistId)}',
    headers: {'Authorization': 'Bearer $token'},
  );
  UserPlaylistLibrary.instance.markChanged();
}

Future<void> deleteUserPlaylistSong(
  String playlistId,
  String itemId,
  String token,
) async {
  final playlist = Uri.encodeComponent(playlistId);
  final item = Uri.encodeComponent(itemId);
  await _client.deleteJson(
    'api/user/music/playlists/$playlist/items/$item',
    headers: {'Authorization': 'Bearer $token'},
  );
  UserPlaylistLibrary.instance.markChanged();
}
```

- [ ] **Step 4: Run the API tests and verify GREEN**

Run: `flutter test test/api_client_test.dart`
Expected: all tests pass.

### Task 3: Playlist-directory single and batch deletion

**Files:**
- Modify: `lib/features/profile/user_playlists_view.dart`
- Test: `test/widget_test.dart`

- [ ] **Step 1: Add failing widget tests**

Inject a fake `UserApi`, load one owned and one remote-favorite playlist, and
verify:

```dart
expect(find.byTooltip('删除歌单'), findsNWidgets(2));
await tester.tap(find.byTooltip('管理歌单'));
await tester.tap(find.text('全选'));
await tester.tap(find.byTooltip('删除所选歌单'));
```

Confirm the fake records one owned deletion and one favorite removal after the
confirmation dialog.

- [ ] **Step 2: Run the focused widget tests and verify RED**

Run: `flutter test test/widget_test.dart --plain-name 'playlist directory supports single and batch deletion'`
Expected: delete/manage controls are absent.

- [ ] **Step 3: Implement management state and deletion dispatch**

Add optional `UserApi api`, a selected-ID set, manage/select-all actions, row
checkboxes, normal-mode delete icons, confirmation dialogs, sequential batch
execution, failure counts, and a single final reload. Dispatch favorites to
`removePlaylistFavorite(source, sourceId, token)` and owned rows to
`deleteUserPlaylist(id, token)`.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run: `flutter test test/widget_test.dart --plain-name 'playlist directory supports single and batch deletion'`
Expected: test passes with no uncaught exceptions.

### Task 4: Owned-playlist track deletion

**Files:**
- Modify: `lib/features/profile/user_playlists_view.dart`
- Modify: `lib/features/profile/user_library_view.dart`
- Test: `test/widget_test.dart`

- [ ] **Step 1: Add a failing detail-page batch-delete test**

Open an owned playlist with two songs whose `libraryId` values are item IDs.
Verify a single row delete and selection-mode delete invoke the supplied
callback with the correct songs. Verify a remote favorite detail exposes no
delete controls.

- [ ] **Step 2: Run the focused test and verify RED**

Run: `flutter test test/widget_test.dart --plain-name 'owned playlist supports track deletion'`
Expected: batch-management controls are absent.

- [ ] **Step 3: Wire existing endpoints into the detail UI**

Pass `onRemove` only for owned/imported playlists. Resolve `song.libraryId`,
call `deleteUserPlaylistSong`, and add detail-page selection mode that invokes
the same callback sequentially. Keep remote favorites read-only.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run: `flutter test test/widget_test.dart --plain-name 'owned playlist supports track deletion'`
Expected: all assertions pass.

### Task 5: Live-TV navigation and toolbox cleanup

**Files:**
- Modify: `lib/features/home/home_shell.dart`
- Modify: `lib/features/tools/tools_view.dart`
- Test: `test/widget_test.dart`

- [ ] **Step 1: Write failing navigation/toolbox tests**

Assert mobile navigation labels are `首页`, `发现`, `搜索`, `我的`; assert the
desktop sidebar has no `直播`; assert `ToolsView` contains `电视直播` but not
`导入歌单`; and verify opening a live channel uses the global pause callback.

- [ ] **Step 2: Run the tests and verify RED**

Run: `flutter test test/widget_test.dart --plain-name 'live TV is available only from toolbox'`
Expected: old live navigation and import card are still visible.

- [ ] **Step 3: Remove duplicate navigation and bind pause behavior**

Reduce the mobile tab mapping to four entries, remove the sidebar live item and
unused root page, remove the toolbox import card/import, and construct
`LiveTvView(onBeforeOpenChannel: context.read<PlayerController>().pause)` from
the toolbox.

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run: `flutter test test/widget_test.dart --plain-name 'live TV is available only from toolbox'`
Expected: test passes.

### Task 6: Verification and Android-only release preparation

**Files:**
- Modify: `pubspec.yaml`
- Verify: `.github/workflows/flutter-release.yml`

- [ ] **Step 1: Run formatting and diff checks**

Run: `dart format` on modified Dart files, then `git diff --check`.
Expected: no formatting or whitespace errors.

- [ ] **Step 2: Run the complete Flutter gates**

Run: `flutter analyze` and `flutter test`.
Expected: zero analyzer errors and all tests pass.

- [ ] **Step 3: Select an unused version/build and build Android release**

Fetch remote tags and online manifests, increment both pubspec values, then run
`flutter build apk --release` using the production signing setup.
Expected: a universal release APK for package `com.music.player`.

- [ ] **Step 4: Verify package metadata and certificate**

Use `aapt` and `apksigner` to confirm version name/code, package ID, and SHA-256
`c6821dcc9ac2395eb9a810f1b9ff250a3a7186ab899fdd8de772d852cf542a72`.

- [ ] **Step 5: Obtain final publication approval**

Report version, build number, commit, `android-ecs-v<version>` tag, generated
`flutter-v<version>` bridge tag, Android-only platform list, and APK/manifest
assets before pushing anything public.

- [ ] **Step 6: Publish and verify both update channels**

Push the branch and Android tag, wait for Android/ECS/GitHub jobs, verify ECS
`latest.json`, HTTP 206 range download, GitHub release ordering and APK asset,
then re-check package metadata and production signature.
