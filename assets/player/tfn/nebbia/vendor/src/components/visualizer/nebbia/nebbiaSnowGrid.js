// Adapted from Folia 5bdade1102f9b80830eec5f523e87f3e2a13d40d; src/components/visualizer/nebbia/nebbiaSnowGrid.ts
// Copyright Folia contributors. AGPL-3.0-only. See app/THIRD_PARTY_NOTICES.md.
import { segDist } from './nebbiaSegments.js';
export class NebbiaSnowGrid {
    cells = [];
    gw = 1;
    gh = 1;
    size = 30;
    reset(W, H, size) {
        this.size = size;
        this.gw = Math.ceil(W / size) + 1;
        this.gh = Math.ceil(H / size) + 1;
        this.cells = Array.from({
            length: this.gw * this.gh
        }, ()=>[]);
    }
    gx(x) {
        return Math.min(this.gw - 1, Math.max(0, Math.floor(x / this.size)));
    }
    gy(y) {
        return Math.min(this.gh - 1, Math.max(0, Math.floor(y / this.size)));
    }
    place(d) {
        if (!this.cells.length) return;
        const c = this.gx(d.x) + this.gy(d.y) * this.gw;
        if (c === d.cell) return;
        this.unplace(d);
        this.cells[c].push(d);
        d.cell = c;
    }
    unplace(d) {
        if (d.cell < 0) return;
        const a = this.cells[d.cell], j = a.indexOf(d);
        if (j >= 0) {
            a[j] = a[a.length - 1];
            a.pop();
        }
        d.cell = -1;
    }
    alongSegments(segs, pad, reach, radius, hit) {
        for(let p = 0; p < segs.length; p += 5){
            const hw = segs[p + 4] / 2, m = hw + pad + reach;
            const x0 = this.gx(Math.min(segs[p], segs[p + 2]) - m), x1 = this.gx(Math.max(segs[p], segs[p + 2]) + m);
            const y0 = this.gy(Math.min(segs[p + 1], segs[p + 3]) - m), y1 = this.gy(Math.max(segs[p + 1], segs[p + 3]) + m);
            for(let gy = y0; gy <= y1; gy += 1)for(let gx = x0; gx <= x1; gx += 1)for (const d of this.cells[gx + gy * this.gw]){
                if (!d.dead && segDist(d.x, d.y, segs, p) < hw + pad + radius(d)) hit(d);
            }
        }
    }
    at(x, y, extra, radius) {
        if (!this.cells.length) return null;
        const cx = this.gx(x), cy = this.gy(y);
        for(let gy = Math.max(0, cy - 1); gy <= Math.min(this.gh - 1, cy + 1); gy += 1)for(let gx = Math.max(0, cx - 1); gx <= Math.min(this.gw - 1, cx + 1); gx += 1){
            for (const d of this.cells[gx + gy * this.gw])if (!d.dead && Math.hypot(d.x - x, d.y - y) < radius(d) + extra) return d;
        }
        return null;
    }
}
