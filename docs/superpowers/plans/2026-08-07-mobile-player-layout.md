# Mobile Full-Screen Player Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the phone-only full-screen player as the approved balanced layout while preserving the desktop player and existing playback behavior.

**Architecture:** Keep `PlayerView` as the platform-responsive entry point. Refactor only its mobile branch so the top bar, switchable cover/lyrics stage, and bottom controls have separate stable constraints; reuse `PlayerController`, `SleepTimer`, `showQueueSheet`, `ArtistNamesLink`, and the existing error actions.

**Tech Stack:** Flutter, Provider, existing DuckMusic design-system widgets, Flutter widget tests.

---

Git commit steps are intentionally omitted because this workspace contains unrelated user changes and no commit was requested.

### Task 1: Add Mobile Player Regression Coverage

**Files:**
- Modify: `test/widget_test.dart:1560`
- Test: `test/widget_test.dart`

- [ ] **Step 1: Extend the mobile player test fixture**

Add teardown calls for the test viewport and create a local pump helper that supplies the current player providers, platform theme, viewport size, and safe-area padding:

```dart
Future<void> pumpPlayer(Size size, TargetPlatform platform) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PlayerController>.value(value: player),
        ChangeNotifierProvider<SettingsController>.value(value: settings),
        ChangeNotifierProvider<AuthController>.value(value: auth),
        ChangeNotifierProvider<SleepTimer>.value(value: timer),
      ],
      child: MaterialApp(
        theme: AppTheme.byId('light').data.copyWith(platform: platform),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            padding: platform == TargetPlatform.iOS
                ? const EdgeInsets.only(top: 47, bottom: 34)
                : const EdgeInsets.only(top: 24, bottom: 24),
          ),
          child: const PlayerView(),
        ),
      ),
    ),
  );
  await tester.pump();
}
```

- [ ] **Step 2: Write the short-screen layout test**

Add a test that pumps `Size(320, 568)`, `Size(375, 667)`, `Size(390, 844)`, and `Size(430, 932)` on Android and iOS. For every size assert:

```dart
expect(find.text('正在播放'), findsOneWidget);
expect(find.bySemanticsLabel('查看歌词'), findsOneWidget);
expect(find.byTooltip('歌词'), findsOneWidget);
expect(find.byTooltip('睡眠定时'), findsOneWidget);
expect(find.byTooltip('播放队列'), findsOneWidget);
expect(find.byTooltip('随机播放'), findsOneWidget);
expect(find.byTooltip('循环模式'), findsOneWidget);
expect(tester.takeException(), isNull);
```

Also assert the play button and the bottom tool row remain inside the viewport by comparing their rectangles with `Offset.zero & size`.

- [ ] **Step 3: Write the cover and lyrics interaction test**

Verify both approved lyric entrances and the stable return action:

```dart
await tester.tap(find.byTooltip('歌词'));
await tester.pump(const Duration(milliseconds: 400));
expect(find.text('穿过人海只为与你相见'), findsOneWidget);
expect(find.byTooltip('返回封面'), findsOneWidget);

await tester.tap(find.byTooltip('返回封面'));
await tester.pump(const Duration(milliseconds: 400));
expect(find.bySemanticsLabel('查看歌词'), findsOneWidget);

await tester.tap(find.bySemanticsLabel('查看歌词'));
await tester.pump(const Duration(milliseconds: 400));
expect(find.text('穿过人海只为与你相见'), findsOneWidget);
```

- [ ] **Step 4: Test that changing songs restores the cover**

Make `_PreviewPlayerController._song` mutable and add this test-only helper:

```dart
void replaceCurrent(Song song) {
  _song = song;
  notifyListeners();
}
```

Enter lyrics, replace the current song, pump one frame, then verify the cover is restored:

```dart
await tester.tap(find.byTooltip('歌词'));
await tester.pump(const Duration(milliseconds: 400));
player.replaceCurrent(
  _song(
    'replacement',
    '下一首测试歌曲',
    artists: const ['测试歌手'],
    albumId: 99,
    album: '测试专辑',
  ),
);
await tester.pump();
expect(find.bySemanticsLabel('查看歌词'), findsOneWidget);
expect(find.text('下一首测试歌曲'), findsOneWidget);
```

- [ ] **Step 5: Verify the tests fail for the current layout**

Run:

```bash
flutter test test/widget_test.dart --name 'mobile full-screen player|iOS player opens'
```

Expected: FAIL because the current cover state has no `歌词` button, the title is duplicated instead of `正在播放`, queue appears twice, shuffle/repeat controls are placeholders, or a short-screen `RenderFlex` overflows.

### Task 2: Separate the Mobile Stage and Stable Controls

**Files:**
- Modify: `lib/features/player/player_view.dart:163-470`
- Test: `test/widget_test.dart`

- [ ] **Step 1: Simplify the mobile top bar**

Keep the left `收起播放器` action, replace the song title/artist block with one centered label, and remove the top queue action:

```dart
const Text(
  '正在播放',
  style: TextStyle(
    color: Colors.white,
    fontSize: 13,
    fontWeight: TypeScale.semibold,
  ),
)
```

The desktop top bar remains unchanged.

- [ ] **Step 2: Move song identity into the bottom control block**

Change `_MobilePlayer` so the `AnimatedSwitcher` owns only the cover/lyrics stage. Pass `song`, `player.error`, `showingLyrics`, `onShowLyrics`, and `onShowCover` into `_MobileControls`:

```dart
return Column(
  children: [
    Expanded(
      child: AnimatedSwitcher(
        duration: Motion.normal,
        child: _showLyrics
            ? _LyricView(
                key: ValueKey('mobile-lyrics-${widget.song.id}'),
                lrc: player.lyric,
                immersive: true,
              )
            : _MobileCoverStage(
                key: ValueKey('mobile-cover-${widget.song.id}'),
                song: widget.song,
                onOpenLyrics: _showLyricsView,
              ),
      ),
    ),
    _MobileControls(
      song: widget.song,
      error: player.error,
      showingLyrics: _showLyrics,
      onShowLyrics: _showLyricsView,
      onShowCover: _showCoverView,
    ),
  ],
);
```

Use private methods that guard redundant `setState` calls:

```dart
void _showLyricsView() {
  if (!_showLyrics) setState(() => _showLyrics = true);
}

void _showCoverView() {
  if (_showLyrics) setState(() => _showLyrics = false);
}
```

- [ ] **Step 3: Replace the rotating disc with responsive square artwork**

Rename `_MobileDiscStage` to `_MobileCoverStage`. Use `LayoutBuilder` and a `FittedBox` so short screens can shrink the square cover without overflow:

```dart
return LayoutBuilder(
  builder: (context, constraints) {
    final widthLimit = MediaQuery.sizeOf(context).width * 0.72;
    final heightLimit =
        (constraints.maxHeight - 20).clamp(120.0, 310.0).toDouble();
    final coverSize = widthLimit.clamp(120.0, heightLimit).toDouble();
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 14),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Semantics(
            button: true,
            label: '查看歌词',
            child: GPressScale(
              onTap: onOpenLyrics,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: ShadowToken.cover(context, radius: 32),
                ),
                child: AsyncCover(
                  url: song.album.picUrl,
                  size: coverSize,
                  radius: 16,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  },
);
```

Remove `_DiscCover` and the unused `dart:math` import after the mobile branch no longer uses rotation.

- [ ] **Step 4: Add the fixed song identity and error slot**

At the top of `_MobileControls`, add a row with song name, `ArtistNamesLink`, and `_FavoriteBtn`. Add a bounded error slot between identity and progress:

```dart
SizedBox(
  height: 58,
  child: error == null
      ? const SizedBox.shrink()
      : _PlaybackErrorBanner(
          message: error!,
          actionLabel: _playbackActionLabel(player),
          onAction: () => _handlePlaybackError(context, player),
        ),
)
```

Keep name at two lines maximum, artist at one line, and place the favorite control in a stable 46pt trailing slot.

- [ ] **Step 5: Run the focused layout tests**

Run:

```bash
flutter test test/widget_test.dart --name 'mobile full-screen player|iOS player opens'
```

Expected: layout assertions pass; control-specific assertions may remain red until Task 3.

### Task 3: Complete the Mobile Playback Controls

**Files:**
- Modify: `lib/features/player/player_view.dart:380-480`
- Test: `test/widget_test.dart`

- [ ] **Step 1: Add shuffle and repeat controls to the transport row**

Replace the two empty 46pt placeholders with working buttons:

```dart
_ImmersiveIconButton(
  icon: Icons.shuffle_rounded,
  tooltip: player.shuffle ? '关闭随机播放' : '随机播放',
  selected: player.shuffle,
  onTap: player.toggleShuffle,
),
```

```dart
_ImmersiveIconButton(
  icon: player.loopMode.name == 'one'
      ? Icons.repeat_one_rounded
      : Icons.repeat_rounded,
  tooltip: '循环模式',
  selected: player.loopMode.name != 'off',
  onTap: player.cycleLoopMode,
),
```

Keep previous, play/pause, and next in their existing center positions.

- [ ] **Step 2: Make the three-item utility row explicit**

Use a fixed three-column row:

```dart
Row(
  mainAxisAlignment: MainAxisAlignment.spaceAround,
  children: [
    _ImmersiveIconButton(
      icon: showingLyrics ? Icons.album_outlined : Icons.lyrics_outlined,
      tooltip: showingLyrics ? '返回封面' : '歌词',
      selected: showingLyrics,
      onTap: showingLyrics ? onShowCover : onShowLyrics,
    ),
    _ImmersiveIconButton(
      icon: Icons.timer_outlined,
      tooltip: '睡眠定时',
      onTap: () => _showSleepTimer(context),
    ),
    _ImmersiveIconButton(
      icon: Icons.queue_music_rounded,
      tooltip: '播放队列',
      onTap: () => showQueueSheet(context),
    ),
  ],
)
```

- [ ] **Step 3: Add selected styling without changing target size**

Extend `_ImmersiveIconButton` with `selected = false` and tint selected controls with the theme accent while preserving its 46x46 target:

```dart
color: selected
    ? Theme.of(context).colorScheme.primary
    : Colors.white.withValues(alpha: 0.92),
```

- [ ] **Step 4: Keep controls stable across cover and lyrics states**

Use the same `_MobileControls` widget in both states and only change the first utility icon/tooltip. Do not conditionally insert or remove transport slots.

- [ ] **Step 5: Run mobile player and navigation tests**

Run:

```bash
flutter test test/widget_test.dart --name 'mobile full-screen player|iOS player opens|Android system back|iOS edge swipe'
```

Expected: PASS with one queue tooltip, stable lyric/cover switching, and no return-gesture regressions.

### Task 4: Verify the Shared Player Surface

**Files:**
- Verify: `lib/features/player/player_view.dart`
- Verify: `test/widget_test.dart`

- [ ] **Step 1: Format the changed files**

Run:

```bash
dart format lib/features/player/player_view.dart test/widget_test.dart
```

Expected: formatter exits successfully.

- [ ] **Step 2: Run the complete widget test file**

Run:

```bash
flutter test test/widget_test.dart
```

Expected: all tests pass.

- [ ] **Step 3: Run focused static analysis**

Run:

```bash
flutter analyze lib/features/player/player_view.dart test/widget_test.dart
```

Expected: `No issues found!`.

- [ ] **Step 4: Check whitespace and final diff**

Run:

```bash
git diff --check
git diff -- lib/features/player/player_view.dart test/widget_test.dart
```

Expected: no whitespace errors; diff is limited to the approved mobile player redesign and its tests.
