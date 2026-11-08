# Global header consistency implementation plan

**Goal:** Use the song cover page's alignment and button feedback across navigation headers, without changing playback or content behavior.

**Architecture:** A shared `GToolbar` owns geometry; `GToolbarButton` owns icon targets and feedback. `GAppBar` supplies the safe area and themed surface. Root page headings use the same first-row baseline and horizontal inset, with subtitles below.

**Constraints:** Preserve existing changes. At most two concurrent tasks. Favorites remain `AppBrand.favoriteRed`. Lyrics contain no rain. Keep desktop window-control clearance and accessibility. Install a debug preview; no production release.

- [x] Add regression coverage comparing cover/lyrics controls and root/detail header alignment, safe areas, long titles and large text.
- [x] Implement common 64-point toolbar, 20-point mobile inset, 48-point button targets, 22-point icons and circular press feedback in `lib/widgets/glass.dart`.
- [x] Migrate player, lyrics, spectrum and panel headers; keep content actions and playback behavior intact.
- [x] Migrate main pages, playlist detail, login and tool headers to the shared components. Remove private offsets and undersized search-clear targets.
- [x] Run focused tests, the full Flutter suite and analyzer, build the Android debug APK, and check navigation plus light/dark appearance in the emulator.
- [x] Document verified results and show a cross-page screenshot comparison.
