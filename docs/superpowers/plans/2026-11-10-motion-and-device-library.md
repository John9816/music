# Reference motion and device music implementation plan

**Goal:** Replace approximate player treatments with the observed TuneFreeNext 4.3.6 behavior and add automatic Android music discovery.

**Architecture:** Keep playback in the existing native audio pipeline. Rendering consumes lyrics and a monotonic playback clock, isolated from UI rebuilds. Device songs are indexed from MediaStore and played through content URIs without copying or deleting the originals.

**Constraints:** Single agent. Preserve red favorites, no rain in lyrics, no player volume slider, independent search sources and production signing. Suspend pending 1.1.59 publication until revisions are verified. The reference package identifies Folia revision 5bdade1102f9b80830eec5f523e87f3e2a13d40d; The user explicitly authorized direct reuse with publication of corresponding source under AGPL-3.0. Do not change unrelated macOS documents or concurrent backend work.

- [x] Capture reference skin states and transitions; record durations and layouts rather than infer them from thumbnails.
- [x] Add tested MediaStore scan/index reconciliation, URI validation, permission state, automatic refresh, deduplication and non-destructive removal.
- [x] Connect the Android bridge on a worker thread; request audio-only permission, observe media changes and refresh after app resume.
- [x] Replace approximate skin rendering and update the player layout, lyric transitions and dynamic cover behavior against runtime evidence.
- [x] Inspect glass navigation and player open/close rendering; eliminate redundant compositing and retain responsive gestures.
- [x] Run focused regression tests, analyzer and full suite; verify scans, playback, skins and transitions on the emulator, including paused/seek/background behavior.
- [ ] Build signed artifacts, push and publish only after all revised behavior and any required renderer license decision are resolved.

Runtime comparison and platform limits are recorded in the 2026-11-10 Android experience release report; identical music-dependent timing is not claimed.
