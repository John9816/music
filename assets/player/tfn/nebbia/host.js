// TFN host for the pinned Folia renderer. All resources are local application assets.
import { NebbiaRuntime } from './vendor/src/components/visualizer/nebbia/createNebbiaRuntime.js';
import { DEFAULT_NEBBIA_TUNING } from './vendor/src/components/visualizer/nebbia/types.js';
import { loadNebbiaStrokes } from './vendor/src/components/visualizer/nebbia/nebbiaStrokes.js';
import { SkinTrackClock } from './track_clock.js';

const host = document.getElementById('window');
const send = (type) => window.TfnNebbiaHost?.postMessage(JSON.stringify({ type }));
let runtime = null, content = null, clock = null, lastSequence = -1;
let destroyed = false;
const trackClock = new SkinTrackClock();
const currentTime = { get: () => (runtime?.renderedSong?.currentTime ?? trackClock.track)?.get() ?? 0 };
const vocal = { get: () => clock?.active && clock?.playing ? clock.vocal : 0 };
const setSong = () => runtime.setSong({
  ...content.song, trackIdentity: content.trackIdentity,
  currentTime: trackClock.track, mixHandoff: content.mixHandoff,
});

function playback() {
  if (!runtime || !clock) return;
  runtime.setTfnActive(clock.active && !document.hidden);
  // Static mode only draws on changed lyric/seek frames, without toggling the
  // pause state on each clock packet.
  runtime.setPlayback(!clock.active || !clock.playing || clock.reduceMotion, clock.reduceMotion);
}
function rebuild() {
  runtime?.destroy();
  runtime = null;
  if (destroyed || !content) return;
  const tuning = { ...DEFAULT_NEBBIA_TUNING, ...content.tuning };
  const behind = tuning.behind;
  try {
    runtime = new NebbiaRuntime({ host, seeThrough: behind === 'backdrop',
      scene: behind === 'aquarium' ? 'aquarium' : 'night', glass: tuning.glass,
      currentTime, vocal,
      onFirstFrame: () => send('frame'),
      onFailed: () => send('failed'), onRestored: rebuild,
    }, content.theme, tuning, content.scale ?? 1);
    runtime.setTfnPerformance(content.performance?.maxFps ?? 60, content.performance?.pixelRatioCap ?? 2);
    runtime.setTfnInsets(content.insets?.top ?? 0, content.insets?.bottom ?? 0, !!clock?.active && !clock?.reduceMotion);
    runtime.setFontScale(content.lyricScale ?? 1);
    setSong();
    runtime.setDaylight(false);
    playback();
  } catch { send('failed'); }
}
window.TfnNebbia = {
  receive(packet) {
    if (destroyed || !Number.isSafeInteger(packet.sequence) || packet.sequence <= lastSequence) return;
    lastSequence = packet.sequence;
    const previousClock = clock;
    if (packet.clock) clock = trackClock.update(packet.clock, packet.content?.trackIdentity ?? packet.content?.song.seed);
    if (packet.content) {
      const previous = content;
      content = packet.content;
      document.documentElement.style.setProperty('--accent', content.theme.backgroundColor);
      if (!runtime || previous?.tuning?.glass !== content.tuning.glass || previous?.tuning?.behind !== content.tuning.behind) rebuild();
      else {
        runtime.setTfnPerformance(content.performance?.maxFps ?? 60, content.performance?.pixelRatioCap ?? 2);
        runtime.setFontScale(content.lyricScale ?? 1);
        runtime.setTheme(content.theme);
        runtime.setTuning({ ...DEFAULT_NEBBIA_TUNING, ...content.tuning });
        runtime.setRenderScale(content.scale ?? 1);
        runtime.setTfnInsets(content.insets?.top ?? 0, content.insets?.bottom ?? 0, !!clock?.active && !clock?.reduceMotion);
        if (previous.songKey !== content.songKey) setSong();
      }
    }
    playback();
    if (clock?.active && (!clock.playing || clock.reduceMotion) &&
        (!previousClock?.active || Math.floor(previousClock.position / 100) !== Math.floor(clock.position / 100))) runtime?.requestFrame();
  },
  dispose() { destroyed = true; runtime?.destroy(); runtime = null; content = null; clock = null; },
};
document.addEventListener('visibilitychange', () => {
  if (document.hidden) runtime?.setTfnActive(false);
  else playback();
});
window.addEventListener('pagehide', () => runtime?.setTfnActive(false));
window.addEventListener('error', () => send('failed'));
window.addEventListener('unhandledrejection', () => send('failed'));
if (await loadNebbiaStrokes()) send('loaded');
else send('failed');
