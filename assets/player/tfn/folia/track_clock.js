// Each rendered song holds its own clock while an incoming scene is built.
export class SkinTrackClock {
  track = null;

  update(sample, seed) {
    if (!this.track || (seed != null && this.track.seed !== seed)) {
      this.track = new TrackClock(seed);
    }
    this.track.sample = { ...sample, at: performance.now() };
    return this.track.sample;
  }
}

class TrackClock {
  constructor(seed) {
    this.seed = seed;
  }

  get() {
    const sample = this.sample;
    if (!sample) return 0;
    const elapsed = sample.playing && sample.active && !document.hidden
      ? Math.max(0, performance.now() - sample.at)
      : 0;
    return Math.min(sample.duration || Infinity, sample.position + elapsed) / 1000;
  }
}
