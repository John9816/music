# Floating navigation and mini player

Implemented the two user-supplied bottom-bar references in the mobile shell:

- Root pages have a floating, icon-only capsule in 首页 / 搜索 / 发现 / 我的 order. The selected page uses a filled capsule highlight. A separate vinyl shortcut opens the player when a song exists.
- Nested pages use a single floating mini player: circular artwork, a one-line title, previous, filled play/pause, and next. Playback progress appears around the disc.
- Both surfaces share the neutral glass rim and light/dark treatment. Smooth rendering and high-contrast settings disable blur. Existing press, keyboard, and reduced-motion behavior is retained.
- Playback failures remain visible, with an error badge and a retry action. Compact desktop layouts retain the queue action.
- The shell reserves space for the dock and system bottom inset; opening the keyboard hides the dock. Explicit StackFit.expand prevents the body from collapsing when the dock is hidden or a nested page has no current song.

## Validation

- 101 focused tests passed, including playback interaction, local-width desktop layout, mobile shell safe areas, and visual fixtures.
- 592 full Flutter tests passed; flutter analyze reported no issues; git diff --check passed.
- Empty playback cases were verified with 0/24 bottom insets. Keyboard visibility retains page content and the expected viewport height. The safe-area regression was first observed at expected 820 / actual 844 before correction.
- Exported actual Flutter render PNGs and visually inspected dark navigation, dark mini player, and light mini player. The final light/dark crop sheet was also inspected.
- A second read-only review found no remaining definite rendering or interaction regression in the scoped changes.

Evidence: `build/qa/reference-dock-2026-11-08/`. Primary logs: `focused-final.log`, `tests-final.log`, `analyze-final.log`, and `safe-area-green.log`. Preview: `floating-dock-preview.png`; source renders: `screenshots/`.

## Delivery boundary

These UI changes are local and have not been packaged or deployed as a new production release. The previously verified 1.1.54 artifacts do not contain this change. No emulator or ADB operation was performed for this task because the user is using the emulator. Visual fixtures use offline sample songs, so unavailable artwork appears as the normal placeholder. Device frame pacing and installation of this new UI were not tested.
