# Folia renderer used by DuckMusic

DuckMusic ships Lumiere (绘光), Hanabi (花火), and Nebbia (雾笺) from
https://github.com/chthollyphile/folia-major at revision
`5bdade1102f9b80830eec5f523e87f3e2a13d40d`, licensed under AGPL-3.0.
Copyright (c) 2026 chthollyphile. Original source copyright notices are retained.
The complete DuckMusic client and its corresponding build sources are distributed
under AGPL-3.0 with this integration; third-party components retain their licenses.

## Build

Use Node.js 22 or newer:

```sh
cd third_party/folia
npm ci --ignore-scripts
npm test
npm run build
cd ../..
flutter pub get
flutter build apk --release
```

The Flutter version is recorded in the release's build verification report.
For a locally installable build, supply your own Android keystore via the ignored
`android/key.properties` as described in RELEASE.md. Production signing credentials
are intentionally not part of the source distribution.

The source release contains all Flutter/native client code, bundled renderer build
inputs, package locks, assets and build scripts. Runtime artifacts are generated at
`assets/player/folia/`. `src/` includes all upstream modules in the esbuild dependency
graph; unrelated Folia application UI, backend and development datasets are omitted.
A checkout of the fixed upstream revision also supplies the original full project.

## DuckMusic modifications, 2026-11-10

- New `host.js`, `clock.mjs`, `entry.ts`, `build.mjs`, and adapters: native clock and
  optional audio-session FFT input; serial/coalesced lyric updates; local WebView;
  explicit pause, visibility and teardown. No account credentials or playback URLs
  cross the rendering bridge. No renderer network access is required.
- The clock stops extrapolating after 250 ms without a fresh native position.
- `nebbiaStrokes.ts`: reads the local injected stroke dataset before fetch fallback.
- Nebbia configuration disables raindrops/dew bumps, as requested by the user.
- Offline drum/stem analysis adapters return no analysis. Hanabi retains its lyric
  program; it does not claim source-separated drum/voice timing for arbitrary tracks.
- Compiled player code is built from upstream source, not extracted TuneFreeNext host
  code. No TuneFreeNext branding, screenshots or skin previews are redistributed.

## Stroke data

`data/strokes.json.gz` is the derived stroke-median dataset distributed with the
reference APK, explicitly licensed under the Arphic Public License. Its source is
AnimCJK revision `99dba566b92daf45ae20d05e6c91d3f68d8619f2`:
https://github.com/parsimonhi/animCJK . The original modification notice and
copyright/license texts are retained in `licenses/`.
DuckMusic's 2026-11-10 change packages these same JSON medians into `strokes.js` for
local loading; glyph data is unchanged. This data remains subject to its own license.

`PROVENANCE.json` records hashes of the upstream archive and packaged dataset.
`THIRD_PARTY_LICENSES.txt` is generated from the licenses of bundled JS dependencies.
The app's About page exposes these notices and the matching complete source archive.

Additional client adaptations: the Lumiere/Hanabi ticker and Nebbia draw loop are
capped at 30 fps on mobile; lyric-size configuration is forwarded through Theme
and each renderer's typography builder. These modified source files contain dated
DuckMusic comments. Default typography uses scale 1. Full lyrics remain available
by tapping the canvas.

Mobile follow-up: lyric weight is forwarded to every renderer. Nebbia bounds its
desktop minimum stroke width by the glyph size so small CJK letters remain open;
drop-free mode omits ink beads/trails as well as field and impact droplets.
Optional WebGL textures receive a transparent 1×1 image at creation, before their
first active frame, for Android WebView sampler completeness.
