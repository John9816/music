// Shared by the two offline renderers. Move existing lyric geometry without
// rebuilding scenes or changing the real playback clock on a control toggle.
export class TfnLyricViewport {
  from = null;
  target = null;
  at = 0;
  duration = 0;
  set(top, bottom, animate = true, now = performance.now()) {
    if (this.target?.top === top && this.target?.bottom === bottom) {
      if (!animate) this.finish();
      return;
    }
    const current = this.sample(now);
    this.from = current ?? { top, bottom };
    this.target = { top, bottom };
    this.at = now;
    this.duration = current && animate ? (bottom > current.bottom ? 600 : 560) : 0;
  }
  finish() { this.duration = 0; }
  get moving() { return this.duration > 0; }
  sample(now = performance.now()) {
    if (!this.target) return null;
    const t = this.duration ? Math.min(1, Math.max(0, (now - this.at) / this.duration)) : 1;
    if (t === 1) { this.finish(); return this.target; }
    // Flutter Curves.easeInOutCubic: cubic-bezier(.645,.045,.355,1).
    let lo = 0, hi = 1;
    const cubic = (u, a, b) => 3*(1-u)*(1-u)*u*a + 3*(1-u)*u*u*b + u*u*u;
    for (let i=0; i<18; i++) {
      const u = (lo+hi)/2;
      if (cubic(u,.645,.355) < t) lo=u; else hi=u;
    }
    const mix = t === 0 ? 0 : cubic((lo+hi)/2,.045,1);
    return {
      top: this.from.top + (this.target.top-this.from.top)*mix,
      bottom: this.from.bottom + (this.target.bottom-this.from.bottom)*mix,
    };
  }
}

// Translate a lyric group's anchor into the new reading area. Only shrink when
// needed to fit; opening more space must not enlarge text beyond its width.
export function tfnProjectLyric(y, height, base, current) {
  const before = Math.max(120, height-base.top-base.bottom);
  const after = Math.max(120, height-current.top-current.bottom);
  return {
    y: current.top + (y-base.top)*after/before,
    scale: Math.min(1, after/before),
  };
}
