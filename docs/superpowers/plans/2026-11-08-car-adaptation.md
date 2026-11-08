# Car Adaptation Implementation Plan

> Implement the two independent paths in the current session, alone, per the latest user instruction, followed by verification and publication.

**Goal:** Add a persisted large-control car mode and Android Auto media integration to the existing Android app.
**Architecture:** Reuse PlayerController and AuthController. A shared CarMediaLibrary supplies session-isolated catalog data to the car UI and SystemMediaController.
**Tech Stack:** Flutter, Provider, audio_service 0.18.19, existing Android media service.
**Spec:** docs/superpowers/specs/2026-11-08-car-adaptation-design.md

## Constraints

- Release baseline was Android 1.1.55+66; locally signed 1.1.56+67 is now verified and published, with 1.1.55 retained for rollback.
- Do not operate the user's emulator or ADB. Preserve unrelated macOS documents.
- Favorites stay red; search source stays independent.
- No dependency upgrades (rxdart is promoted from the already locked transitive version) or second player/login subsystem.

## Task 1: Direct-install vehicle UI (root)

Files: SettingsController, SettingsView, HomeShell; new features/car/car_home_view.dart and car_player_panel.dart; test/car_mode_test.dart and visual QA fixtures.

- [x] Write a regression that restores car_mode_enabled and expects the car home with large accessible controls; run against existing HomeShell and observe missing car UI.
- [x] Persist car mode and add a settings entry. HomeShell changes its presentation while keeping the existing state/callbacks and PlayerController alive.
- [x] Implement responsive navigation + player + lazy song list. Consume context.read<CarMediaLibrary>().songsFor(parentId), search(query), and change notifications. Isolate requests with a generation counter and discard outdated results.
- [x] Verify progress scrubbing with PlaybackTime, three-state mode cycling, playback/skip controls, exit persistence, search and retry. Export and inspect rendered short/wide/narrow/large-text views.

## Task 2: Android Auto catalog and commands

Files: new core/player/car_media_library.dart; SystemMediaController, app.dart, AndroidManifest.xml, res/xml/automotive_app_desc.xml; dedicated catalog/system tests. PlayerController and playback_mode_button.dart may change only to accurately represent externally requested repeat-off while preserving normal three-state cycling.

- [x] Specify and test CarMediaLibrary(auth, player, settings, downloads), songsFor(String), search(String), mediaIdFor(Song), songForMediaId(String); queueId/favoritesId/recentId/downloadsId roots.
- [x] Implement bounded/session-isolated data access and change notification, with no reload for playhead ticks.
- [x] Implement Android Auto declaration and browser callbacks, stable IDs, search and play commands; use the existing player.
- [x] Verify session recovery/logout/races, source-sensitive IDs, search failures and playback mode mappings. Confirm existing iOS/Android notifications remain compatible.

## Task 3: Shared verification and local artifact (root)

- [x] Review all changes, run targeted and full tests plus analyze.
- [x] Build a distinct next-version local signed APK and inspect package/signature/manifest/media resources then publish a new version after verification, keeping 1.1.55 for rollback.
- [x] Document tested behavior, screenshot paths and remaining physical-head-unit/OEM validation.
- [x] Complete ECS publication, GitHub artifact mirror and online verification.

## Latest scope (2026-11-09)
- Preserve production identity; validate package/signature/version before install, distinguish development app and guard its updater.
- Remove theme-color/glass-quality/reduced-motion/general-notification rows, retain media notifications.
- Make dock glass and visible tab transitions independent of the removed preferences; respect system accessibility.
- Audit standard media sessions for Xiaomi/vivo/OPPO/Honor. Do not claim proprietary certification or physical-device results.
- Complete both car modes, commit and push source, build locally with production signing, publish ECS and mirror identical artifacts to GitHub.

Implementation and qualification boundaries: ../research/2026-11-09-android-update-car-media.md. Physical-device testing remains outside the verified evidence; no emulator operations were performed.

Publication evidence: ../research/2026-11-09-android-1.1.56-release.md. Android 1.1.56+67 uses source f408fd6; ECS/web/GitHub checks passed and artifact-only mirror run 42503868805 succeeded.
