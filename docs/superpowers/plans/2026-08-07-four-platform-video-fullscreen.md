# DuckMusic Four-Platform Video Fullscreen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make live TV and VOD playback enter native fullscreen on Android, iOS, macOS, and Windows without adding seek behavior to live streams.

**Architecture:** Reuse `media_kit_video`'s public fullscreen implementation on every platform. Live TV keeps its serialized MPV session and gains a fullscreen-only custom control surface; VOD moves behind an injectable media session backed by `media_kit`, preserving progress persistence and casting behavior.

**Tech Stack:** Flutter, Dart, media_kit, media_kit_video, flutter_test

---

### Task 1: Live TV Fullscreen Contract

**Files:**
- Modify: `lib/features/live_tv/live_player_view.dart`
- Modify: `test/live_player_view_test.dart`

- [ ] **Step 1: Write the failing fullscreen button test**

Extend `_FakeLiveMediaSession` with `fullscreenToggleCount`, implement `toggleFullscreen`, tap `find.byKey(const ValueKey('live-fullscreen-button'))`, and expect the count to become one. Also assert that the live view contains no `VideoProgressIndicator` or `Slider`.

- [ ] **Step 2: Run the test and verify RED**

Run: `flutter test test/live_player_view_test.dart --plain-name 'live player exposes fullscreen without seek controls'`

Expected: compilation failure because `LiveMediaSession.toggleFullscreen` and the fullscreen button do not exist.

- [ ] **Step 3: Add the minimal fullscreen contract**

Add this method to `LiveMediaSession`:

```dart
Future<void> toggleFullscreen();
```

Add an icon button to the existing live control row:

```dart
IconButton(
  key: const ValueKey('live-fullscreen-button'),
  tooltip: '全屏',
  onPressed: _media.toggleFullscreen,
  icon: const Icon(Icons.fullscreen),
)
```

- [ ] **Step 4: Connect the media_kit VideoState**

Give `_MediaKitLiveMediaSession` a `GlobalKey<VideoState>`, pass it to `Video`, and implement:

```dart
Future<void> toggleFullscreen() async {
  await _videoKey.currentState?.toggleFullscreen();
}
```

- [ ] **Step 5: Run the live player tests and verify GREEN**

Run: `flutter test test/live_player_view_test.dart`

Expected: all live player tests pass.

### Task 2: Live Fullscreen Control Surface

**Files:**
- Modify: `lib/features/live_tv/live_player_view.dart`
- Modify: `test/live_player_view_test.dart`

- [ ] **Step 1: Write a failing no-seek control test**

Add a widget test for a small exported/internal live controls widget. In fullscreen mode it must expose exit-fullscreen, mute, play/pause, and route actions, while `Slider`, `VideoProgressIndicator`, and seek icons remain absent.

- [ ] **Step 2: Run the focused test and verify RED**

Run: `flutter test test/live_player_view_test.dart --plain-name 'fullscreen live controls never expose seeking'`

Expected: failure because the live fullscreen controls do not exist.

- [ ] **Step 3: Implement custom media_kit controls**

Pass a `VideoControlsBuilder` to the live `Video`. Build a transparent `GestureDetector` that toggles fullscreen on desktop double-click and a bottom-right control row. Use `isFullscreen(context)` to show expanded controls only in fullscreen, and call `toggleFullscreen(context)` for enter/exit. Do not add any timeline or horizontal seek gesture.

- [ ] **Step 4: Run live queue, failover, and player tests**

Run: `flutter test test/live_open_queue_test.dart test/live_line_failover_test.dart test/live_player_view_test.dart`

Expected: all tests pass.

### Task 3: Injectable VOD Media Session

**Files:**
- Create: `lib/features/videos/video_media_session.dart`
- Create: `test/video_media_session_test.dart`
- Modify: `lib/features/videos/video_player_view.dart`

- [ ] **Step 1: Write the failing session contract tests**

Define tests around a fake session for these behaviors: opening the exact direct URL, seeking to `resumePosition` before play, reporting current position, pausing on cast connection, toggling fullscreen, and disposing once.

- [ ] **Step 2: Run the tests and verify RED**

Run: `flutter test test/video_media_session_test.dart`

Expected: failure because `VideoMediaSession` does not exist.

- [ ] **Step 3: Define the session interface**

Create:

```dart
abstract class VideoMediaSession {
  bool get isPlaying;
  Duration get position;
  double get aspectRatio;
  Future<void> open(Uri uri, {Duration resumePosition = Duration.zero});
  Future<void> play();
  Future<void> pause();
  Future<void> toggleFullscreen();
  Future<void> dispose();
  Widget buildVideo();
}
```

- [ ] **Step 4: Implement the media_kit session**

Use one `Player`, one `VideoController`, and one `GlobalKey<VideoState>`. Open with `play: false`, seek when the resume position is valid, then play. Return a `Video` with adaptive controls so VOD retains its progress bar, seeking, playback controls, double-click behavior, and fullscreen exit button.

- [ ] **Step 5: Inject the session into VideoPlayerView**

Add an optional `VideoMediaSessionFactory`. Replace `VideoPlayerController` state reads with the session contract, keep the five-second history timer, and keep `_handleCastState` pausing the session when requested.

- [ ] **Step 6: Run VOD tests and verify GREEN**

Run: `flutter test test/video_media_session_test.dart test/video_views_test.dart test/video_history_service_test.dart test/cast_service_test.dart`

Expected: all tests pass.

### Task 4: Cross-Platform Fullscreen Regression Coverage

**Files:**
- Modify: `test/video_views_test.dart`
- Modify: `test/live_player_view_test.dart`

- [ ] **Step 1: Add button and lifecycle assertions**

Verify live and VOD both expose stable fullscreen keys, a tap delegates exactly once, the full-screen operation does not reopen media, and disposing a route still disposes the session once.

- [ ] **Step 2: Run all player tests**

Run: `flutter test test/live_player_view_test.dart test/video_media_session_test.dart test/video_views_test.dart`

Expected: all tests pass.

- [ ] **Step 3: Run the full suite and analyzer**

Run: `flutter test`

Expected: all tests pass.

Run: `flutter analyze`

Expected: `No issues found!`

### Task 5: Platform Builds and macOS Runtime Verification

**Files:**
- Verify only; do not stage or commit the dirty worktree.

- [ ] **Step 1: Build Android**

Run: `flutter build apk --debug`

Expected: Debug APK builds successfully.

- [ ] **Step 2: Build iOS without signing**

Run: `flutter build ios --debug --no-codesign`

Expected: iOS app builds successfully without signing.

- [ ] **Step 3: Build macOS**

Run: `flutter build macos --debug`

Expected: `build/macos/Build/Products/Debug/7511.app` is produced.

- [ ] **Step 4: Account for Windows host limitation**

Run: `flutter build windows --debug` only on a Windows host. On macOS, verify that the Windows media_kit plugin remains registered and report that a Windows binary cannot be produced on this host.

- [ ] **Step 5: Exercise macOS fullscreen**

Open CCTV1, enter fullscreen from the button, exit with `Esc`, enter again by double-clicking, return to the channel list, and quit the app. Confirm there is no new `7511-*.ips` crash report.

- [ ] **Step 6: Final format and diff checks**

Run: `dart format --output=none --set-exit-if-changed lib/features/live_tv lib/features/videos test/live_player_view_test.dart test/video_media_session_test.dart test/video_views_test.dart`

Run: `git diff --check`

Expected: both commands exit successfully.

No commit steps are included because the current task explicitly preserves the user's existing dirty worktree without staging or committing.
