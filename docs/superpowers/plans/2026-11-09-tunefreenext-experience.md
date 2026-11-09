# TuneFreeNext Experience Implementation Plan

> Execute inline with superpowers:executing-plans. User explicitly requires single agent.

**Goal:** Implement working roaming, skins, audio EQ, glass navigation and reference search/library.
**Architecture:** Keep PlayerController as playback owner. Separate Qishui roaming state, equalizer controller and visual stages from the existing large views. SettingsController persists visual selections; dedicated audio EQ preferences hold frequencies/gains.
**Tech Stack:** Flutter, just_audio native Android equalizer, liquid_glass_widgets MIT, existing authenticated REST client.
**Spec:** ../specs/2026-11-09-tunefreenext-experience.md

## Global constraints
Single agent. Favorites red. No lyric rain or song volume slider. Independent search source. Preserve com.music.player and production certificate. Do not touch concurrent backend edits or unrelated release docs.

- [x] Add persisted player skin/fluid/cover/glass options and native equalizer adapter/UI. Test preferences roundtrip, native gain bounds and bypass before wiring.
- [x] Add Qishui feed DTO/API and roaming controller. Test sequence retry, duplicate suppression, late-account results and manual-queue exit. Wire mode selector, queue prefetch and discover entry.
- [x] Add lifecycle-aware artwork motion and five lyric stages, skin picker and settings. Preserve full lyric switching and progress. Verify paused/reduced-motion and no overflows.
- [x] Replace mobile nav with three labeled glass tabs plus mini-player. Restore LibraryView with six functional rows and local file import. Preserve desktop/sidebar, nested navigation and back.
- [x] Align search field/segments/scopes/history/results and suggestions. Keep request-version guards and continuous pagination. Enable black artists/albums supported by backend.
- [x] Verify cold black stream loading behavior; add delayed-load regression and appropriate source-specific timeout.
- [x] Analyze and all tests; compare emulator screenshots and exercise skin/EQ/search/library/roaming. Inspect newest backend API deployment.
- [ ] Commit/push and build signed 1.1.59+70 locally. Verify ECS manifest/APK/certificate/Range and GitHub mirror. Record exact evidence and remaining platform limits.
