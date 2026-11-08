# Lyric Appearance Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement these tasks inline. Preserve the ongoing player changes and verify before completion.

**Goal:** Let users adjust lyric size and style in Settings with an immediate preview and persistent playback appearance.

**Architecture:** SettingsController owns a bounded integer size and a typed style preference. A shared typography helper supplies identical text metrics to preview, line measurement, and karaoke rendering. Both full player and desktop panel recalculate their scroll geometry when typography changes.

**Tech Stack:** Flutter, Provider, SharedPreferences, existing KaraokeLyricText.

**Spec:** User request in this conversation: “我希望可以在设置里面调整歌词字体大小和样式”. Decisions: 20–40 in steps of 2, default 28; 标准 (medium), 柔和 (light, slightly spaced), 粗体 (current default); live preview; restore defaults. System text scaling remains supported. Compact views retain their proportional sizing.

## Global Constraints

- Preserve existing uncommitted work, word timings and lyric focus interactions.
- No additional dependencies, network fonts, publication or version change.
- All preferences apply immediately and survive app restart.
- No active/inactive font-metric differences that could change wrapping.

### Task 1: Persist lyric appearance

Files: `lib/core/settings/lyric_appearance.dart`, `lib/core/settings/settings_controller.dart`, `test/lyric_appearance_test.dart`.

Interfaces: `int lyricFontSize`, `LyricFontStyle lyricFontStyle`; `Future<void> setLyricFontSize(int)`, `setLyricFontStyle(LyricFontStyle)`, `resetLyricAppearance()`; `lyricTextStyle(TextStyle base, {required int fontSize, required LyricFontStyle fontStyle, double scale = 1})`.

- [x] Write and run failing defaults/persistence/invalid-storage/reset tests. Example: `await settings.setLyricFontSize(36); await restored.load(); expect(restored.lyricFontSize, 36);`.
- [x] Add keys `lyric_font_size` and `lyric_font_style`; clamp size on read/write, reject unknown style by restoring bold. Notify immediately, then persist.
- [x] Run `flutter test --no-pub test/lyric_appearance_test.dart`.

### Task 2: Preview and player integration

Files: `lib/features/settings/lyric_settings_view.dart`, `lib/features/settings/settings_view.dart`, `lib/features/player/player_view.dart`, `lib/features/player/desktop_player_panel.dart`, player and appearance tests.

- [x] Add widget tests that drag the size slider and tap “柔和”; check preview TextStyle and a newly loaded controller. Test restore defaults and 320px-wide, 2x system text scaling.
- [x] Add “歌词显示” row in 外观, opening a scrollable page constrained to 640px width. Show three static preview lines with partial word highlight, size slider, 3 style choices and reset. Reuse SettingsGroup/GPressScale controls.
- [x] Use shared typography for player layout and highlight. Test live update at the same position: `expect(tester.getCenter(line).dy, closeTo(tester.getCenter(list).dy, 1));` and verify word progress remains intact.
- [x] Replace desktop fixed `index * 58` scrolling with TextPainter-measured rows and cumulative offsets; keep all focus states at the same metrics.
- [x] Run focused tests and existing karaoke/presentation tests.

### Task 3: Verification

- [x] Run full `flutter test --no-pub`, `flutter analyze --no-pub`, and `git diff --check` using the configured runtime.
- [x] Build/install Android debug, open settings, adjust size/style, inspect lyric rendering, restart and verify persistence. Record screenshots and findings.
- [x] Report the settings entry, controls, verified behavior and debug installation. Leave production release untouched.
