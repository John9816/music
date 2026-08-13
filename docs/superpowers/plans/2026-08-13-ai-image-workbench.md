# AI Image Workbench Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a responsive AI image workbench backed by the documented generation, editing, task recovery, history, sharing, deletion, and retry APIs.

**Architecture:** Keep network behavior in `AiDrawApi` with small immutable response models. Keep `AiDrawView` responsible for page state and responsive composition, using existing glass/theme primitives only where they fit the approved darkroom-white direction. Desktop uses a split workbench; mobile uses a single-column flow with a collapsible controls section and horizontal queue.

**Tech Stack:** Flutter/Dart, Material widgets, existing `ApiClient`, `file_selector`, `image_picker`, Provider auth state.

---

### Task 1: Expand image API models and operations

**Files:**
- Modify: `lib/core/api/ai_draw_api.dart`
- Test: `test/ai_draw_api_test.dart`

- [ ] Add immutable models for resumable task records and image history records, parsing the documented `items`, `result.data`, timestamps, sharing, and error fields.
- [ ] Add API methods for `tasks`, `history`, `setShared`, `deleteHistory`, and `retry`, using `getJson`, `patchJson`, `deleteJson`, and `postJson`.
- [ ] Preserve existing async polling behavior and expose the task id/result metadata needed by the page.
- [ ] Add focused tests for parsing and endpoint request shapes, then run `flutter test test/ai_draw_api_test.dart`.

### Task 2: Write widget behavior tests

**Files:**
- Modify: `test/widget_test.dart` or create `test/ai_draw_view_test.dart`

- [ ] Cover mode switching, mobile layout rendering at a narrow surface, parameter controls, and retry action visibility for a failed task.
- [ ] Run the focused widget tests and confirm they fail against the current single-form page before implementation.

### Task 3: Rebuild the AI image workbench

**Files:**
- Modify: `lib/features/tools/ai_draw_view.dart`

- [ ] Add state for size, count, history, resumable tasks, selected history item, and drawer/controls expansion.
- [ ] Load models, resumable tasks, and history after login; refresh history after completion and mutation.
- [ ] Implement desktop split layout and mobile single-column layout using `LayoutBuilder` around 760 logical pixels.
- [ ] Implement generate/edit controls, source image preview, loading/error/empty states, image result actions, queue cards, history grid/list, sharing toggle, delete confirmation, and failed-task retry.
- [ ] Keep all interactive controls keyboard/focus accessible and use existing theme colors with the approved visual tokens.

### Task 4: Verify and polish

**Files:**
- Modify: `lib/features/tools/ai_draw_view.dart` if needed after verification

- [ ] Run `flutter analyze`.
- [ ] Run focused API and widget tests, then the full test suite if the focused suite is green.
- [ ] Inspect desktop and mobile screenshots or widget dimensions, fixing overflow, clipped text, and controls below 44 logical pixels.
