# Mobile Experience Polish

**Goal:** Improve the browse, play, and return flow and make the existing Flutter project directly runnable from Android Studio.

**Design:** Keep the existing neutral light/dark surfaces and user-selected accent. Use album artwork as the visual focus, compact content sections, 48dp Android targets, and a single set of motion tokens. Navigation and loading must preserve the user's place. Reduced motion must stop continuous animation as well as transitions.

**Architecture:** Extend the existing glass controls, HomeShell, DiscoverView, and player widgets. Preserve the current audio, account, and API contracts. Use a shared Flutter debug run configuration and document local SDK requirements.

**Validation:** Focused widget tests for refresh retention, touch targets, loading geometry, reduced motion, player gestures, and narrow layouts; Flutter analysis and the existing regression suite; Android debug APK build and launch when an Android device is available.

- [x] Inspect the existing design system, mobile navigation, player, and Android configuration.
- [x] Make shared controls stable during loading, accessible, and responsive to large text.
- [x] Add consistent bottom navigation selection motion and remove duplicate haptics.
- [x] Make the home feature area compact and preserve content during refresh.
- [x] Complete player dismissal, reduced motion, and song identity handling.
- [x] Verify tests, analysis, Android build, and startup; document exact results.

## Verification (2026-09-08)

- `flutter test --no-pub --reporter expanded`: 278 tests passed. Coverage includes retained refresh content and scroll position, retry actions, 320px layouts with large text, Android touch targets, semantic actions, player dismissal, lyrics tracking, empty and short queues, and reduced motion.
- `flutter analyze --no-pub`: no issues found.
- `flutter build apk --debug --no-pub`: successful. Output: `build/app/outputs/flutter-apk/app-debug.apk`.
- Android Studio recognized the shared `DuckMusic Android` configuration and launched `lib/main.dart` on `Medium_Phone` (`emulator-5554`, API 37.1). IDE hot restart also succeeded.
- Visually checked the home page, mini player, full player, queue, and song information sheet. Verified downward player dismissal and queue expansion on the emulator. The song information sheet also passed an eight-size Android/iOS layout matrix.
- Fixed the custom cover cache's missing image-resizing interface. A real bitmap decode/resize regression test failed before the fix and passed afterward; actual album artwork then rendered after Android Studio hot restart.
- Installed and started the final APK with `flutter run -d emulator-5554 --debug --no-resident --no-pub --use-application-binary=build/app/outputs/flutter-apk/app-debug.apk`; command exited successfully.
- `git diff --check`: passed. Logs are saved under `build/ui-polish-*.log`.

Validation used an Android emulator and Flutter widget tests. Physical-device frame-time profiling and iOS device execution were not part of this pass.
