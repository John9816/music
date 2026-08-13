# Red-source Playlist Cover Compatibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve playlist covers when a music-source response uses `picUrl` or `coverImgUrl` instead of `coverUrl`.

**Architecture:** Normalize source-specific response fields once in `Playlist.fromV1`, keeping the rest of the UI dependent only on `Playlist.coverUrl`. The canonical `coverUrl` remains highest priority and blank values fall through to compatibility fields.

**Tech Stack:** Dart, Flutter test

---

### Task 1: Add playlist cover parsing coverage

**Files:**
- Create: `test/playlist_model_test.dart`
- Test: `test/playlist_model_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:duck_music/core/models/playlist.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Playlist.fromV1 cover URL', () {
    test('falls back to picUrl', () {
      final playlist = Playlist.fromV1({
        'id': 1,
        'name': 'Red source playlist',
        'picUrl': 'https://example.com/pic.jpg',
      });

      expect(playlist.coverUrl, 'https://example.com/pic.jpg');
    });

    test('falls back to coverImgUrl after blank fields', () {
      final playlist = Playlist.fromV1({
        'id': 1,
        'name': 'Red source playlist',
        'coverUrl': ' ',
        'picUrl': '',
        'coverImgUrl': 'https://example.com/cover-img.jpg',
      });

      expect(playlist.coverUrl, 'https://example.com/cover-img.jpg');
    });

    test('prefers canonical coverUrl', () {
      final playlist = Playlist.fromV1({
        'id': 1,
        'name': 'Playlist',
        'coverUrl': 'https://example.com/canonical.jpg',
        'picUrl': 'https://example.com/fallback.jpg',
      });

      expect(playlist.coverUrl, 'https://example.com/canonical.jpg');
    });
  });
}
```

- [ ] **Step 2: Run the test to verify the regression**

Run: `flutter test test/playlist_model_test.dart`

Expected: the `picUrl` and `coverImgUrl` fallback tests fail because `Playlist.fromV1` returns null.

### Task 2: Normalize playlist image fields

**Files:**
- Modify: `lib/core/models/playlist.dart:32`
- Test: `test/playlist_model_test.dart`

- [ ] **Step 1: Implement the minimal fallback chain**

```dart
coverUrl: _optionalText(json['coverUrl']) ??
    _optionalText(json['picUrl']) ??
    _optionalText(json['coverImgUrl']),
```

- [ ] **Step 2: Run focused tests**

Run: `flutter test test/playlist_model_test.dart`

Expected: all playlist model tests pass.

- [ ] **Step 3: Run related regression tests**

Run: `flutter test test/widget_test.dart test/playlist_detail_mobile_view_test.dart`

Expected: all related tests pass without new errors.

- [ ] **Step 4: Format and inspect the diff**

Run: `dart format lib/core/models/playlist.dart test/playlist_model_test.dart`

Run: `git diff --check -- lib/core/models/playlist.dart test/playlist_model_test.dart`

Expected: formatting succeeds and `git diff --check` produces no output.

No commit is created because the existing worktree contains unrelated user changes and the user did not request a commit.
