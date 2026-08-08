# Home Latest Albums Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every latest-album card on the home page open its song detail page and place the latest-albums shelf before daily recommendations.

**Architecture:** Keep `DiscoverView` responsible for loading home data and initiating navigation. Reuse the existing `PlaylistDetailView` album loader pattern from search, passing the active music source and album metadata; add optional `MusicApi` injection only to make home behavior deterministic in widget tests.

**Tech Stack:** Flutter, Dart, Provider, `flutter_test`

---

## File Structure

- Create `test/discover_view_test.dart`: focused widget tests and a deterministic `MusicApi` fake for home ordering and album navigation.
- Modify `lib/features/discover/discover_view.dart`: optional API injection, sliver ordering, album navigation, and clickable album cards.

No API endpoint, data model, player controller, or separate album detail page is added.

### Task 1: Add deterministic API injection without changing runtime behavior

**Files:**
- Modify: `lib/features/discover/discover_view.dart:14-37`
- Test: `test/widget_test.dart:1750-1791`

- [ ] **Step 1: Run the existing DiscoverView smoke coverage**

Run:

```bash
flutter test test/widget_test.dart --plain-name "primary content pages render at desktop and compact widths"
```

Expected: PASS before the refactor.

- [ ] **Step 2: Add optional API injection**

Change the widget and state initialization to:

```dart
class DiscoverView extends StatefulWidget {
  const DiscoverView({
    super.key,
    this.title = '发现',
    this.subtitle,
    this.api,
  });

  final String title;
  final String? subtitle;
  final MusicApi? api;

  @override
  State<DiscoverView> createState() => _DiscoverViewState();
}

class _DiscoverViewState extends State<DiscoverView> {
  late final MusicApi _api;
  late Future<(List<Song>, List<Album>)> _future;
  Future<(List<Song>, List<Album>)>? _loadingFuture;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? MusicApi();
    _future = _startLoad();
  }
```

The default constructor path still creates `MusicApi()`, so production behavior is unchanged.

- [ ] **Step 3: Re-run the existing smoke coverage**

Run:

```bash
flutter test test/widget_test.dart --plain-name "primary content pages render at desktop and compact widths"
```

Expected: PASS with no new exceptions.

### Task 2: Move latest albums before daily recommendations

**Files:**
- Create: `test/discover_view_test.dart`
- Modify: `lib/features/discover/discover_view.dart:98-163`

- [ ] **Step 1: Create the focused test harness and failing order test**

Create `test/discover_view_test.dart` with:

```dart
import 'package:duck_music/core/api/music_api.dart';
import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:duck_music/core/models/song.dart';
import 'package:duck_music/core/player/player_controller.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:duck_music/core/theme/app_theme.dart';
import 'package:duck_music/features/discover/discover_view.dart';
import 'package:duck_music/widgets/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('latest albums appear before daily recommendations',
      (tester) async {
    final api = _FakeDiscoverMusicApi();
    await _pumpDiscover(tester, api);

    final latestTitle = find.descendant(
      of: find.byType(SectionHeader),
      matching: find.text('最新专辑'),
    );
    final dailyTitle = find.descendant(
      of: find.byType(SectionHeader),
      matching: find.text('每日推荐'),
    );

    expect(tester.getTopLeft(latestTitle).dy,
        lessThan(tester.getTopLeft(dailyTitle).dy));
  });
}

Future<void> _pumpDiscover(
  WidgetTester tester,
  _FakeDiscoverMusicApi api,
) async {
  SharedPreferences.setMockInitialValues(const {});
  final settings = SettingsController();
  await settings.setSource('qq');
  final player = PlayerController(settings: settings);
  final auth = AuthController();
  addTearDown(player.dispose);
  addTearDown(settings.dispose);
  addTearDown(auth.dispose);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1000, 1000);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PlayerController>.value(value: player),
        ChangeNotifierProvider<SettingsController>.value(value: settings),
        ChangeNotifierProvider<AuthController>.value(value: auth),
      ],
      child: MaterialApp(
        theme: AppTheme.byId('light').data,
        home: DiscoverView(api: api),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeDiscoverMusicApi extends MusicApi {
  final daily = const [
    Song(
      id: 'daily-1',
      name: '每日歌曲',
      source: 'qq',
      artists: [Artist(id: 7, name: '每日歌手')],
      album: Album(id: 8, name: '每日专辑'),
      durationMs: 180000,
    ),
  ];

  final albums = const [
    Album(id: 42, name: '测试新专辑'),
  ];

  @override
  Future<List<Song>> getDailyRecommend({String source = 'netease'}) async {
    return daily;
  }

  @override
  Future<List<Album>> getNewestAlbums({String source = 'netease'}) async {
    return albums;
  }
}
```

- [ ] **Step 2: Run the order test and verify RED**

Run:

```bash
flutter test test/discover_view_test.dart --plain-name "latest albums appear before daily recommendations"
```

Expected: FAIL because the current latest-albums header has a greater vertical position than the daily-recommendations header.

- [ ] **Step 3: Move the complete latest-albums pair of slivers**

In the `CustomScrollView.slivers` list, keep the page header and hero first, then move this complete block before the daily header and daily `SliverList`:

```dart
SliverToBoxAdapter(
  child: SectionHeader(
    '最新专辑',
    action: Text(
      '${albums.length} 张',
      style: TextStyle(
        fontSize: 12,
        color: Theme.of(context).colorScheme.outline,
      ),
    ),
  ),
),
SliverToBoxAdapter(
  child: SizedBox(
    height: 172,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      itemCount: albums.length,
      separatorBuilder: (_, __) => const SizedBox(width: 14),
      itemBuilder: (context, i) => _AlbumCard(album: albums[i]),
    ),
  ),
),
```

- [ ] **Step 4: Run the order test and verify GREEN**

Run:

```bash
flutter test test/discover_view_test.dart --plain-name "latest albums appear before daily recommendations"
```

Expected: PASS.

- [ ] **Step 5: Commit the order behavior**

```bash
git add test/discover_view_test.dart lib/features/discover/discover_view.dart
git commit -m "feat: prioritize latest albums on home"
```

### Task 3: Open album song details from the home card

**Files:**
- Modify: `test/discover_view_test.dart`
- Modify: `lib/features/discover/discover_view.dart:1-12,151-160,322-325,377-416`

- [ ] **Step 1: Extend the fake and add the failing navigation test**

Add this import:

```dart
import 'package:duck_music/features/playlists/playlist_detail_view.dart';
```

Add this test inside `main`:

```dart
testWidgets('latest album opens its song detail page with current source',
    (tester) async {
  final api = _FakeDiscoverMusicApi();
  await _pumpDiscover(tester, api);

  await tester.tap(find.text('测试新专辑'));
  await tester.pumpAndSettle();

  expect(find.byType(PlaylistDetailView), findsOneWidget);
  final detail = tester.widget<PlaylistDetailView>(
    find.byType(PlaylistDetailView),
  );
  expect(detail.playlist.id, 42);
  expect(detail.playlist.name, '测试新专辑');
  expect(detail.playlist.source, 'qq');
  expect(api.albumDetailRequests.single, ('42', 'qq'));
});
```

Extend `_FakeDiscoverMusicApi` with:

```dart
final albumDetailRequests = <(String, String)>[];

@override
Future<List<Song>> getAlbumDetail(
  String id, {
  String source = 'netease',
  int offset = 0,
  int limit = 100,
}) async {
  albumDetailRequests.add((id, source));
  return daily;
}
```

- [ ] **Step 2: Run the navigation test and verify RED**

Run:

```bash
flutter test test/discover_view_test.dart --plain-name "latest album opens its song detail page with current source"
```

Expected: FAIL because tapping the current `_AlbumCard` does not push any route.

- [ ] **Step 3: Add album navigation and make the whole card interactive**

Add imports:

```dart
import '../../core/models/playlist.dart';
import '../playlists/playlist_detail_view.dart';
```

Add this method to `_DiscoverViewState`:

```dart
void _openAlbum(BuildContext context, Album album) {
  final source = context.read<SettingsController>().source;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => PlaylistDetailView(
        playlist: Playlist(
          id: album.id,
          name: album.name,
          source: source,
          coverUrl: album.picUrl,
        ),
        loader: () => _api.getAlbumDetail(
          album.id.toString(),
          source: source,
        ),
      ),
    ),
  );
}
```

Pass the callback from the shelf:

```dart
itemBuilder: (context, i) => _AlbumCard(
  album: albums[i],
  onTap: () => _openAlbum(context, albums[i]),
),
```

Update `_AlbumCard` so its constructor requires `onTap`, then wrap the existing fixed-width card in `GPressScale`:

```dart
class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.album, required this.onTap});

  final Album album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GPressScale(
      onTap: onTap,
      child: SizedBox(
        width: 140,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: AsyncCover(url: album.picUrl, size: 140, radius: 14),
            ),
            const SizedBox(height: 8),
            Text(
              album.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the focused test file and verify GREEN**

Run:

```bash
flutter test test/discover_view_test.dart
```

Expected: both tests PASS, the fake records `('42', 'qq')`, and there are no pending exceptions.

- [ ] **Step 5: Commit the album navigation behavior**

```bash
git add test/discover_view_test.dart lib/features/discover/discover_view.dart
git commit -m "fix: open latest album details from home"
```

### Task 4: Final verification

**Files:**
- Verify: `lib/features/discover/discover_view.dart`
- Verify: `test/discover_view_test.dart`

- [ ] **Step 1: Format the changed Dart files**

Run:

```bash
dart format lib/features/discover/discover_view.dart test/discover_view_test.dart
```

Expected: both files are formatted successfully.

- [ ] **Step 2: Run focused and existing regression tests**

Run:

```bash
flutter test test/discover_view_test.dart
flutter test test/widget_test.dart --plain-name "primary content pages render at desktop and compact widths"
```

Expected: all selected tests PASS.

- [ ] **Step 3: Run static analysis for changed files**

Run:

```bash
flutter analyze lib/features/discover/discover_view.dart test/discover_view_test.dart
```

Expected: `No issues found!`

- [ ] **Step 4: Inspect the final diff**

Run:

```bash
git diff --check
git diff -- lib/features/discover/discover_view.dart test/discover_view_test.dart
```

Expected: no whitespace errors; the diff contains only API injection, block ordering, album navigation, card interaction, and focused tests.
