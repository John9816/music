# DuckMusic controls aligned with TuneFreeNext

User direction: use REA and the installed TuneFreeNext Android app to align DuckMusic's controls and layouts. Approved ADB interaction on 2026-11-07. Implementation is local; no publishing or account changes.

## Reference and evidence

Reference package `com.sayqz.tunefreenext.app`, version 4.3.5 (9), APK SHA256 `02e1c8541e9087807d69c567adb91202183379b304a9e14f929c2aab04a4a5da`.
REA evidence and runtime captures are in `build/qa/tunefree-alignment-2026-11-07/`.
Static inventory and Dart AOT analysis establish a Flutter app and packaged resources; they do not recover original Dart source, widget trees, or precise design tokens. Screenshots supply the layout evidence. Measurements below are implementation approximations at the emulator's 2.625 device scale.

Observed reference screens: explore, library, profile, storage/settings, playlist, song menu, mini player, full player, search, search results and queue. See the reference ledger for REA evidence IDs.

- Near-black neutral canvas, charcoal grouped surfaces, low contrast separators; accent appears mainly on selected navigation, icons and actions.
- Compact centered navigation title; roughly 20 logical-pixel content gutters. Bold section headings, regular-weight readable rows.
- Three-tab reference navigation uses bare outline/filled icons and labels. DuckMusic keeps its existing destinations and navigation behavior while adopting this visual treatment.
- Library uses a flat, spacious list with accent icons and inset separators, followed by square artwork shelves.
- Profile/settings use rounded grouped rows and colored square icons, clear right-hand values and chevrons.
- Song rows use rounded square artwork, 2-line metadata and a plain ellipsis. Menus use a compact rounded surface with consistent action rows.
- Mini player sits flush above navigation with square artwork and plain play/next controls; full player uses large rounded artwork, ambient background, a fine progress track, prominent transport icons and quiet secondary controls.

## Implementation decisions

Keep DuckMusic's brand accent choices, API/data contracts and all existing functional entry points. Align neutral surfaces, typography, spacing, icon presentation, navigation and media controls with the reference. Preserve desktop structure and keyboard/accessibility behaviors. Reduce decorative outlines, heavy shadows, excessive pill containers and small bold text. Use existing efficient player subscriptions and cover decoding; no shader extraction or new runtime dependencies.

## Work packages

1. Shared theme and controls: neutral palette, typography, centered mobile toolbar, buttons, chips, list and menu surfaces. Owner: primary agent.
2. Shell/library/discover: bare mobile navigation and integrated playback dock, flat library rows, artwork-led shelves. Owner: navigation agent, disjoint files.
3. Mini/full player: artwork proportions, control styles, spacing and progress treatment, preserve all playback actions. Owner: player agent, disjoint files.
4. Profile/settings/search: grouped icon rows, compact search/filter controls and consistent page margins. Owner: primary agent (settings/profile may be delegated with explicit ownership).
5. Verify: existing widget, interaction, responsive and performance tests; offline screenshot fixtures before/after; analyzer; debug APK build and emulator smoke check. Do not use stale test results as proof.

Runtime follow-up: `UserLibraryView` is a separate implementation for owned playlists, favorites and history. Align its mobile hero, play/download/filter controls, row typography, anchored song menu and large-text sizing too. Preserve synchronization, search, management and deletion flows. Both search toggles clear the query when closed.

## Acceptance and boundaries

All sampled control families must be aligned, with visual evidence and responsive checks. Every existing destination, back action, seek, playback toggle, queue and setting remains reachable. Test 320px large text, phone, landscape and desktop. Report any unobserved reference screens or unverified runtime states honestly. Original Android notification crash finding is separate and remains documented pending resource verification; do not silently bundle a speculative crash fix.

## Follow-up polish pass

User requested continued detail polishing on 2026-11-07. Preserve the approved visual direction and finish these bounded refinements:

- Distinguish first-load, empty, refreshing and refresh-error states in owned playlists/favorites/history. Preserve loaded artwork, songs and scroll position on refresh; reset cached data when switching content.
- Make empty-state guidance match the library kind, connect desktop filtering, and anchor the library toolbar menu to its real button bounds.
- Correct nested-route playback padding using the system inset above Scaffold; verify gesture navigation and keyboard insets.
- Quiet compact search pagination while retaining page indicators, disabled states, retry and large-text usability.
- Validate with regression tests, screenshot fixtures, full suite, independent review and a freshly installed debug APK. Retain evidence in `build/qa/tunefree-polish-2026-11-07/`.
