// Adapted from Folia 5bdade1102f9b80830eec5f523e87f3e2a13d40d; src/components/visualizer/nebbia/nebbiaSnowTrails.ts
// Copyright Folia contributors. AGPL-3.0-only. See app/THIRD_PARTY_NOTICES.md.
import { clamp, MASK_SCALE, smooth } from './nebbiaConstants.js';
const MOVE_MIN = 3;
const WIPE_CLEAR = 0.5;
export class NebbiaSnowTrails {
    list = [];
    clear() {
        this.list.length = 0;
    }
    track(wipe, x, y, w) {
        if (!wipe) {
            const n = {
                pts: [
                    x,
                    y
                ],
                w,
                end: null
            };
            this.list.push(n);
            return n;
        }
        const p = wipe.pts;
        wipe.w = Math.max(wipe.w * 0.98, w);
        if (Math.hypot(x - p[p.length - 2], y - p[p.length - 1]) > MOVE_MIN) p.push(x, y);
        return wipe;
    }
    draw(ctx, time, hold, refog) {
        ctx.setTransform(MASK_SCALE, 0, 0, MASK_SCALE, 0, 0);
        for(let i = this.list.length - 1; i >= 0; i -= 1){
            const wp = this.list[i];
            const v = wp.end === null ? 1 : 1 - smooth(clamp((time - wp.end - hold * 0.5) / (refog * 0.6)));
            if (v <= 0.002) {
                this.list.splice(i, 1);
                continue;
            }
            const p = wp.pts;
            if (p.length < 4) continue;
            ctx.moveTo(p[0], p[1]);
            for(let j = 2; j < p.length; j += 2)ctx.lineTo(p[j], p[j + 1]);
            ctx.stroke(wp.w, v * WIPE_CLEAR);
        }
        ctx.setTransform(1, 0, 0, 1, 0, 0);
    }
}
