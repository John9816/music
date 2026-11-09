# TuneFreeNext experience alignment

The user requests music roaming, player skins, a real equalizer, liquid glass navigation, fluid artwork backgrounds, animated cover artwork, and matching TuneFreeNext search/library screens. Single agent; ADB authorized. Reference installed version 4.3.6, screenshots under build/qa/tunefreenext-ui-2026-11-09. REA evidence ev_4dd266ca46628d9f73971b754077314350d70069826e99a830212d457858eae6 proves packaged Flutter and liquid_glass_widgets strings, not exact implementation.

## Navigation and visual contract
Mobile tabs: 探索 / 资料库 / 我的; search remains a separate retained page opened from exploration. Existing desktop sidebar stays available. Glass navigation has labels and a persistent full mini player above it. Search uses search field + cancel, four inline source segments, compact result scopes, recent-search rows, and two-column colored suggestion cards. Static suggestions are labelled 搜索推荐 rather than presented as live popularity. Library uses six pink-icon rows, separators, 最近添加 and two-column artwork cards. Local music supports user-picked audio files stored locally; favorites and created playlists open their actual filtered lists.

Colors: background #0D1017, diffuse #253342, text #F5F5F7, secondary #9D9DA5, accent #FF2D55, favorite #FF3B30. Respect existing light mode and large text. Reference geometry at 1080x2400 / 2.625 density: 20dp margins, 48dp minimum touch targets, 52dp library rows, 56dp song art.

## Playback additions
Roaming uses authenticated Qishui feed modes + session start/next/close, opaque IDs, server sequence and expiry. Never replay mutations under a changed auth account. Prefetch near queue end, deduplicate, cap memory, preserve active track. Manual playQueue exits roaming; network error keeps current playback and exposes retry. Switching mode starts a fresh feed and user/account changes discard pending responses.

Five local skins: 经典 / 大字海报 / 雾笺 / 绘光 / 花火. Reconstruct visual treatments from observed screenshots, no proprietary shader extraction. Nonclassic stages show synchronized current/next lyrics; full lyrics view remains accessible with seek and karaoke. 雾笺 uses mist only: no raindrops. No volume slider on song page. Favorite always red. Dynamic artwork slowly transforms existing art; fluid background uses bounded art decode and low-frequency transforms. Animations pause offscreen, when paused, in background, and when system disableAnimations is true.

Android equalizer uses just_audio AndroidEqualizer in the actual playback pipeline. Read native band frequencies/ranges; persist presets and custom gains by frequency, expose bypass and reset. Unsupported platforms show an honest state. Prevent boost clipping by normalizing requested gains so maximum applied gain is 0dB; do not pretend a limiter exists.

## Validation and release
Meaningful regression tests cover auth/session races, queue continuation, settings persistence, actual equalizer adapter, slow Qishui loads, search source isolation, navigation and library actions. Visual fixture comparison at reference density and small/large text sizes. Android emulator verifies sound effects and navigation; production signing/package preserved. Local release 1.1.59+70 to ECS + GitHub binary mirror after checks. No backend stale deployment: inspect newest committed source and concurrent work before deploy.
