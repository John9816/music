# DuckMusic Figma Prototype Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create and verify an editable Figma Design prototype for DuckMusic across desktop and mobile, covering the full navigational product surface and clickable flows.

**Architecture:** Use one new Figma Design file with pages for Foundations, Components, Desktop Screens, Mobile Screens, and Prototype Map. Build reusable components first, then compose screen frames from those components. Use the existing Flutter theme tokens and screen structure as the source of truth; use local sample content and representative cover placeholders.

**Tech Stack:** Figma MCP `create_new_file`, `use_figma`, `get_screenshot`, and `get_metadata`; Flutter source files under `lib/`; existing palette and spacing tokens in `lib/core/theme/design_tokens.dart`.

---

### Task 1: Create and inspect the Figma file

**Files:**
- Read: `DESIGN.md`
- Read: `lib/core/theme/design_tokens.dart`
- Read: `lib/features/home/home_shell.dart`
- Read: `lib/features/home/home_view.dart`
- Read: `lib/features/player/player_view.dart`

- [ ] Call `whoami` and resolve the single available Figma plan key.
- [ ] Call `create_new_file` with editor type `design` and file name `DuckMusic Product Prototype`.
- [ ] Inspect pages, local variables, existing components, and available libraries in the new file before mutating the canvas.
- [ ] Record the returned `file_key` and `file_url` for the handoff.

### Task 2: Build foundations and reusable components

**Files:**
- Read: `lib/widgets/glass.dart`
- Read: `lib/core/theme/app_theme.dart`

- [ ] Create a Foundations page with dark palette swatches, typography samples, spacing scale, and radius samples.
- [ ] Create reusable component frames for desktop sidebar, mobile bottom navigation, Mini Player, section header, song row, playlist card, search field, segmented control, setting tile, dialog, empty state, and loading state.
- [ ] Use loaded fonts and return every created node ID from each `use_figma` call.
- [ ] Capture screenshots of the component page and correct clipped text or broken auto-layout before composing screens.

### Task 3: Compose desktop screens

**Files:**
- Read: `lib/features/discover/discover_view.dart`
- Read: `lib/features/search/search_view.dart`
- Read: `lib/features/library/library_view.dart`
- Read: `lib/features/profile/profile_view.dart`
- Read: `lib/features/settings/settings_view.dart`
- Read: `lib/features/tools/tools_view.dart`
- Read: `lib/features/books/book_reader_view.dart`

- [ ] Create `1440 x 900` frames for Home, Discover, Search, Library, Player, Profile, Settings, Books, and Tools.
- [ ] Append sections directly into wrapper frames: sidebar, top bar/content header, content sections, and Mini Player.
- [ ] Use component instances or detached editable component-like frames for repeated patterns.
- [ ] Capture and review screenshots after the first four screens and after the remaining screens.

### Task 4: Compose mobile screens

**Files:**
- Read: `lib/features/home/home_shell.dart`
- Read: `lib/features/player/mini_player.dart`
- Read: `lib/features/player/player_view.dart`

- [ ] Create `390 x 844` frames for Home, Search, Library, Player, and Profile.
- [ ] Replace desktop sidebar with bottom navigation and preserve the Mini Player above it.
- [ ] Validate safe spacing, readable labels, and no overlap between player controls, Mini Player, and bottom navigation.
- [ ] Capture a mobile page screenshot for final visual verification.

### Task 5: Wire and validate the prototype

**Files:**
- Figma Prototype Map page

- [ ] Add prototype connections for Home → Search, Home → Discover, result/detail → Player, Player → Queue/Lyrics, Player → Library, and Library → playlist/detail.
- [ ] Add secondary connections for login, theme selection, notifications, storage, books, video parsing, and AI drawing.
- [ ] Inspect metadata to ensure every connection target exists and every repeated surface remains editable.
- [ ] Capture final desktop and mobile screenshots and report the Figma URL plus any residual limitations.
