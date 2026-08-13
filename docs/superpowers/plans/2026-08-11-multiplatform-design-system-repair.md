# Multiplatform Design System Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repair DuckMusic's shared visual system while preserving all user-selectable theme colors.

**Architecture:** Keep `ColorScheme` as the single color contract, but separate neutral surfaces from user accents and derive foreground contrast. Centralize semantic breakpoints in `GBreakpoints`, make pointer/scroll behavior platform-aware, and adapt the existing authentication primitives rather than introducing a second component library.

**Tech Stack:** Flutter, Dart, Material 3, Cupertino icons, flutter_test

---

### Task 1: Accessible accent themes

**Files:**
- Modify: `lib/core/theme/design_tokens.dart`
- Modify: `lib/core/theme/app_theme.dart`
- Create: `test/design_system_regression_test.dart`

- [ ] Write a test that iterates through `AppAccent.all`, builds light and dark themes, asserts the selected accent remains `scheme.primary`, checks `onPrimary` contrast is at least 4.5:1, and confirms surfaces do not change between accents.
- [ ] Run `flutter test test/design_system_regression_test.dart` and confirm the contrast and neutral-surface assertions fail.
- [ ] Add fixed 7511 green/yellow tokens, neutral surface tables, and computed black/white `onPrimary` and `onPrimaryContainer` colors.
- [ ] Run the test again and confirm it passes.

### Task 2: Coherent responsive and desktop interaction behavior

**Files:**
- Modify: `lib/widgets/glass.dart`
- Modify: `lib/app.dart`
- Modify: `lib/features/player/player_view.dart`
- Modify: `lib/features/discover/discover_view.dart`
- Test: `test/design_system_regression_test.dart`

- [ ] Add failing tests for the semantic breakpoint helpers and for desktop pointer/scroll behavior.
- [ ] Run the focused tests and confirm they fail for the missing helpers and desktop affordances.
- [ ] Add `contentSplit` to `GBreakpoints`, use `sidebar` for the full player split, provide Windows/Linux hover/cursor feedback in `GPressScale`, and make the app scroll behavior show desktop scrollbars without reintroducing the macOS MouseTracker path.
- [ ] Add explicit previous/next controls around the desktop latest-albums rail so it is usable without horizontal trackpad gestures.
- [ ] Run focused shell/player/discover tests and confirm they pass.

### Task 3: Responsive authentication layout

**Files:**
- Modify: `lib/features/profile/login_view.dart`
- Test: `test/design_system_regression_test.dart`

- [ ] Add failing mobile and desktop widget tests asserting persistent field labels, wrapping consent copy, minimum readable text sizes, and vertically balanced desktop content.
- [ ] Run the focused tests and confirm they fail against the placeholder-only, top-aligned form.
- [ ] Update `_AuthPage` to center vertically on wide/tall windows while retaining scroll safety, add labels to `_AuthField`, and let the consent/recovery actions wrap.
- [ ] Run authentication and existing password-field tests and confirm they pass.

### Task 4: Documentation and full verification

**Files:**
- Modify: `DESIGN.md`

- [ ] Update the design documentation to describe seven accents, neutral surfaces, current `DiscoverView` home, and semantic breakpoints.
- [ ] Run `dart format` on changed Dart files.
- [ ] Run `flutter analyze`.
- [ ] Run the full Flutter test suite.
- [ ] Build/run macOS and launch the iOS simulator build for screenshot review at desktop and phone sizes.
