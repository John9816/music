// Adapted from Folia 5bdade1102f9b80830eec5f523e87f3e2a13d40d; src/components/visualizer/nebbia/nebbiaCondensation.ts
// Copyright Folia contributors. AGPL-3.0-only. See app/THIRD_PARTY_NOTICES.md.
import { createVisualizerRng } from '../visualizerSeedHash.js';
import { segDist } from './nebbiaSegments.js';
const AREA_PER_DROP = 81;
const MAX_DEW = 1.5;
const FIRST_FILL = 10, GROW = 6, FADE = 4;
const LIFE_MIN = 12.5, LIFE_SPAN = 25;
const UPDATE_EVERY = 0.05;
const CELL = 24, REGROW_MIN = 2, REGROW_SPAN = 4;
export class NebbiaCondensation {
    list = [];
    inst = new Float32Array(0);
    rng = createVisualizerRng(9191);
    W = 0;
    H = 0;
    time = 0;
    sinceUpdate = 0;
    lastSize = -1;
    lastCount = -1;
    dirty = true;
    changed = true;
    cells = [];
    cellOf = new Int32Array(0);
    gw = 1;
    wetAt = -Infinity;
    build(W, H) {
        this.W = W;
        this.H = H;
        this.time = 0;
        this.wetAt = -Infinity;
        const n = Math.round(W * H / AREA_PER_DROP * MAX_DEW);
        this.list = Array.from({
            length: n
        }, ()=>this.spawn(this.rng() * FIRST_FILL));
        this.inst = new Float32Array(n * 6);
        this.gw = Math.ceil(W / CELL) + 1;
        this.cells = Array.from({
            length: this.gw * (Math.ceil(H / CELL) + 1)
        }, ()=>[]);
        this.cellOf = new Int32Array(n);
        this.list.forEach((d, i)=>{
            this.cellOf[i] = this.cellAt(d.x, d.y);
            this.cells[this.cellOf[i]].push(i);
        });
        this.dirty = true;
    }
    cellAt(x, y) {
        const gh = this.cells.length / this.gw;
        return Math.min(this.gw - 1, Math.max(0, Math.floor(x / CELL))) + Math.min(gh - 1, Math.max(0, Math.floor(y / CELL))) * this.gw;
    }
    touchInk(sweeps, wet, size) {
        if (sweeps.length) this.wipe(sweeps, 0, size);
        if (!wet.length || this.time - this.wetAt < UPDATE_EVERY) return;
        this.wetAt = this.time;
        this.wipe(wet, 2, size);
    }
    wipe(segs, pad, size = 1) {
        const { gw, cells, list, time } = this, gh = cells.length / gw;
        for(let p = 0; p < segs.length; p += 5){
            const m = segs[p + 4] / 2 + pad + 5 * size;
            const x0 = Math.max(0, Math.floor((Math.min(segs[p], segs[p + 2]) - m) / CELL)), x1 = Math.min(gw - 1, Math.floor((Math.max(segs[p], segs[p + 2]) + m) / CELL));
            const y0 = Math.max(0, Math.floor((Math.min(segs[p + 1], segs[p + 3]) - m) / CELL)), y1 = Math.min(gh - 1, Math.floor((Math.max(segs[p + 1], segs[p + 3]) + m) / CELL));
            for(let gy = y0; gy <= y1; gy += 1)for(let gx = x0; gx <= x1; gx += 1)for (const i of cells[gx + gy * gw]){
                const d = list[i];
                if (i >= this.lastCount || d.born > time + REGROW_MIN * 0.5 || segDist(d.x, d.y, segs, p) >= segs[p + 4] / 2 + pad + d.r * size) continue;
                if (d.born <= time) d.full = false;
                d.born = time + REGROW_MIN + this.rng() * REGROW_SPAN;
            }
        }
    }
    spawn(born) {
        const { rng } = this;
        const y = this.H * (1 - rng() ** 1.4), low = y / Math.max(1, this.H);
        const r = rng() < 0.06 + 0.08 * low ? 3 + rng() * (0.55 + 0.7 * low) : 1.2 + rng() ** 1.5 * (1.35 + 0.4 * low);
        return {
            x: rng() * this.W,
            y,
            r,
            sy: 1 + rng() * 0.2,
            born,
            life: LIFE_MIN + rng() * LIFE_SPAN,
            full: false
        };
    }
    instances(dt, dew = 1, size = 1) {
        const out = this.inst;
        this.time += Math.min(dt, 0.1);
        this.sinceUpdate += Math.min(dt, 0.1);
        const now = this.time;
        const n = Math.min(this.list.length, Math.round(this.list.length * dew / MAX_DEW));
        const resized = size !== this.lastSize;
        let changed = this.dirty || resized || n !== this.lastCount;
        if (!changed && this.sinceUpdate < UPDATE_EVERY) {
            this.changed = false;
            return out.subarray(0, n * 6);
        }
        this.sinceUpdate = 0;
        if (resized) for (const d of this.list)d.full = false;
        for(let i = 0; i < n; i += 1){
            let d = this.list[i];
            if (now - d.born > GROW + d.life + FADE) {
                d = this.list[i] = this.spawn(now + this.rng() * 3);
                const c = this.cellAt(d.x, d.y), old = this.cells[this.cellOf[i]];
                old.splice(old.indexOf(i), 1);
                this.cells[c].push(i);
                this.cellOf[i] = c;
            }
            const age = now - d.born;
            const full = age >= GROW && age <= GROW + d.life;
            if (full && d.full) continue;
            const grow = Math.min(1, Math.max(0, age / GROW)), fade = Math.min(1, Math.max(0, (GROW + d.life + FADE - age) / FADE));
            const r = d.r * size * Math.sqrt(grow) * Math.sqrt(fade);
            const w = r < 0.5 ? 0 : r * 8, o = i * 6;
            out[o] = d.x;
            out[o + 1] = d.y;
            out[o + 2] = w;
            out[o + 3] = w * d.sy;
            out[o + 4] = w / 100;
            out[o + 5] = 1;
            d.full = full;
            changed = true;
        }
        this.lastSize = size;
        this.lastCount = n;
        this.dirty = false;
        this.changed = changed;
        return out.subarray(0, n * 6);
    }
}
