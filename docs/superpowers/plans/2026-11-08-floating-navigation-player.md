# Floating navigation and mini player

Implement the two supplied bottom-bar references in the existing mobile shell. Root pages use an icon-only navigation capsule and a separate vinyl player shortcut. Nested pages show a single playback capsule with vinyl artwork, one-line title, previous, play/pause, and next controls.

Constraints: retain 首页 / 搜索 / 发现 / 我的; retain red favorites; respect keyboard, system insets, large text, and reduced motion; preserve desktop queue access. At most two concurrent tasks. The user is using the emulator, so do not run ADB or install an app. The published 1.1.54 artifacts remain the preceding release.

- [x] Implement the shared glass capsule, icon navigation, and vinyl shortcut.
- [x] Replace the mobile mini player with the reference control hierarchy.
- [x] Cover navigation, playback actions, error recovery, and responsive layout in existing tests.
- [x] Verify empty playback safe areas and retain compact desktop queue controls.
- [x] Run affected tests, full Flutter tests, and static analysis.
- [x] Export and inspect actual Flutter renders in light/dark modes.
- [x] Record the validation and supply the local preview.
