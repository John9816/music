# Global header and control consistency

The song cover page is the geometry reference for navigation controls. Previously, root headers, detail headers, lyrics, spectrum, playlists and tool screens each owned different padding and button dimensions.

## Shared components

- `GToolbar`: 64 logical pixels high; 8 vertical inset; 20 horizontal inset below 600 logical pixels and 24 above. Adjacent actions have an 8-pixel gap. Desktop window controls remain clear. The containing page owns the safe area.
- `GToolbarButton`: 48 × 48 target; 22 icon; transparent circular surface and 0.92 press scale. Keyboard, tooltips, accessibility and reduced motion use the existing `GPressScale` behavior.
- `GAppBar`: themed surface and one safe area around `GToolbar`; inherits the user's selected font.
- `GPageHeader`: the title and action share a minimum 48-pixel first row, with secondary text below it. Long actions and large text retain their responsive stacking behavior.
- Existing content `GIconButton` now shares circular 0.92 press feedback. Content cards retain their own quieter feedback.

## Migrated surfaces

Cover, immersive lyrics, frequency view, desktop player panel and queue; home, discover, search, profile, library and playlist detail; login, reader and video/live TV tool screens. Settings and ordinary detail pages inherit the shared app bar. Removed private header insets and undersized search-clear targets.

Lyrics' cover-return target was 58 pixels and displaced the entire header. It is now 48, matching the cover's favorite target. The frequency view's back control now shares the cover's left inset and icon shape. Playlist search, scrolling title visibility, filtering and menu access are retained.

On top of playlist artwork, the shared controls use white icons and a translucent dark circle for contrast. Once the toolbar becomes pinned or search opens, they return to the normal themed foreground. This avoids dark controls disappearing into dark artwork.

Favorites keep `AppBrand.favoriteRed`. Emulator inspection also found that profile list rows ignored this semantic color. `SettingsRow.fixedIconColor` now preserves it for favorite songs and favorite playlists without recoloring other list entries.

## Verification

- Alignment regression tests first failed against the previous 4-pixel detail inset and the lyrics header's shifted baseline, then passed after migration.
- Tests cover safe areas, narrow layouts with multiple actions, large text, complete button targets, custom fonts, desktop window controls, playback navigation and profile favorite colors.
- Final full Flutter suite: **576 passed**.
- Final `flutter analyze --no-pub`: **No issues found**.
- Debug APK built with `--dart-define=APP_VERSION=1.1.53-reference`; installed as `com.music.player.debug`. Production is unchanged.
- Logs: `build/qa/lotus-style-2026-11-08/header-final-tests.log`, `header-final-analyze.log`, `header-build.log`.

Emulator screenshots and final navigation observations are saved in the same QA directory with the `header-` prefix.

Runtime verification scope: navigation and layout were checked on the emulator. The restored track `netease:1964850580` returned `no playable url` when playback was attempted, so this run does not establish live stream or lyric timing availability for that track. No backend or source logic was changed by this task.

Final APK SHA-256: `e117fe1acd061852c37257ca068777a5b700a69f19e8b0c8e79555567b679e9b`.

Emulator observations: cover, lyric, settings and playlist leading targets all measured `[53,84][179,210]` physical pixels at 1080×2400; root-page heading centers share the same vertical center. Checked light/dark home, profile and settings; playlist scrolling and artwork contrast; restored Android night mode to its original `no` value. Screenshot comparison: `build/qa/lotus-style-2026-11-08/header-comparison.png`.
