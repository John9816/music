# Music list, search, and player refinement

The user requested seven bounded changes to existing screens. The approved playback modes are 列表循环 / 单曲循环 / 随机播放.

- [x] Align song lists to the prior reference: artwork, title and artist on separate lines, red favorite button, vertical overflow, quieter row separation. Reuse one account-scoped favorite snapshot instead of issuing a request per row; refresh on music-library changes.
- [x] Replace search previous/next page controls with guarded append pagination; retain the list on failure and expose retry. Discard responses after query/type/source changes.
- [x] Reclaim mobile search height with a compact query/source toolbar and category row; keep lazy result rendering, source independence, and large-text support.
- [x] Use one playback-mode control across player and desktop surfaces. List loop and random must disable native single-track looping; single loop must disable shuffle.
- [x] Use the root app theme for the artist chooser so immersive player text colors cannot leak onto light sheet surfaces; verify selecting an artist still opens details.
- [x] The player's song-operation sheet retains download only. Contextual song-list/queue and playlist-management operations remain available in their own locations.
- [x] Hide the membership redemption entry/dialog and remove dead-end redemption prompts; retain membership status and error retry.
- [x] Run targeted regression tests, full Flutter suite, analyzer, and exported visual QA; record results and local release status.

Constraints: preserve the preceding floating dock work, red favorites, and independent search source. At most two concurrent tasks. No ADB/emulator operations. The user subsequently authorized local Android packaging and ECS deployment before vehicle adaptation. Avoid unrelated local documentation changes.
