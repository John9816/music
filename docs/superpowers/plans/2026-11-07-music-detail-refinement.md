# Music detail refinement implementation plan

> **For agentic workers:** Use superpowers:executing-plans and superpowers:dispatching-parallel-agents for independent file ownership. Keep all work in the current authorized workspace.

**Goal:** Implement the five UI refinements accepted by the user: compact playlist hero, clean song rows, better cover states, independent homepage sections, consistent secondary pages.

**Architecture:** Preserve Flutter providers, API contracts and the previously aligned theme. Split only homepage request state; keep reusable artwork behavior in AsyncCover and optional library deletion in the existing song action menu.

**Tech Stack:** Flutter/Dart, provider, cached_network_image, Android ADB/REA.

**Spec:** User accepted all five recommendations in this conversation; established style and constraints are in `2026-11-07-tunefree-control-alignment.md`.

## Constraints

- Preserve unrelated edits, existing music destinations, album/song actions, account data, themes and desktop responsiveness.
- No publish, release, commit or push. User has authorized ADB navigation; only primary agent controls the emulator.
- Run only one Flutter test process at a time; primary coordinates regression and final runs.
- Missing artwork must differ from failed artwork; a retry must not accidentally trigger parent playback/navigation. Avoid retaining unrelated songs' artwork.
- Independent homepage sections must preserve successful cached content on refresh and expose targeted retry when the other section fails.

## Tasks

1. **Playlist hierarchy and rows** (primary): shorten mobile artwork space in `user_library_view.dart` and `playlist_detail_view.dart` to approximately 0.46 of viewport width, bounded for landscape; retain title wrapping and large text. Extend `SongActionButton`/`showSongActions` with an optional library remove callback and label. Move the existing single-row remove action there, keeping batch management. Verify menu removal, cancellation, long names, small and landscape layouts.
2. **Artwork states** (cover agent): update `async_cover.dart` and relevant focused tests. Loading shows a quiet placeholder; missing URL shows music art fallback; failure shows a retry action with accessible label; retries retain dimensions and request headers. Preserve disk/memory limits, reduced motion, Hero behavior and same-resource cached artwork. Prove failure→retry→success with a controlled image loader, not external network.
3. **Independent homepage loading** (discover agent): replace joint `Future.wait` rendering in `discover_view.dart` with independent daily/albums state. A completed section renders without waiting for the other. Preserve refresh scroll and interactive cached data, suppress duplicate in-flight loads and support section retry. Tests use Completers for both completion orders, single failures/retry and refresh preservation.
4. **Secondary pages** (secondary agent): align `user_playlists_view.dart`, `downloads_view.dart`, and artist/search selection sheets with 20dp gutters, quiet toolbar actions, square covers and readable text. Preserve deletion/import/download behaviors. Avoid fixed-height text clipping; add only meaningful interaction/layout regression tests.
5. **Integration and runtime verification** (primary): read all diffs, run focused tests serially, analyzer, screenshot fixtures, full suite and independent review. Build/install debug APK with replacement, inspect actual playlist/search/download states. Run bounded playback/background/lock/resume/next smoke and inspect current-process error logs; report its limits and do not claim original production crash solved.

## Validation commands

Use `build/qa/tunefree-alignment-2026-11-07/run-ui-tests.sh` for Flutter tests; source-specific tests first, then the full `test` suite. Export screenshots with `DUCKMUSIC_EXPORT_QA=true` and the existing Chinese QA font define. Run `dart analyze lib test` with `DEVELOPER_DIR=/Library/Developer/CommandLineTools`, plus working fallback git `diff --check`. Save all new evidence under `build/qa/tunefree-refinement-2026-11-07/`.
