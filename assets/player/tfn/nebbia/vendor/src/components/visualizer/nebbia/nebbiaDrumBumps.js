// Adapted from Folia 5bdade1102f9b80830eec5f523e87f3e2a13d40d; src/components/visualizer/nebbia/nebbiaDrumBumps.ts
// Copyright Folia contributors. AGPL-3.0-only. See app/THIRD_PARTY_NOTICES.md.
import { DRUM_KICK } from '../../../services/analysis/drumHits.js';
const MIN_STRENGTH = 0.35;
const MIN_GAP = 0.3;
const MAX_STEP = 0.5;
export class NebbiaDrumBumps {
    list = null;
    key = null;
    next = 0;
    lastT = -Infinity;
    lastBump = -Infinity;
    step(hits, key, T) {
        if (hits !== this.list || key !== this.key) {
            this.list = hits;
            this.key = key;
            this.seek(T);
            return 0;
        }
        if (T < this.lastT || T - this.lastT > MAX_STEP) {
            this.seek(T);
            return 0;
        }
        let amount = 0;
        const { times, strengths, kinds } = hits;
        for(; this.next < times.length && times[this.next] <= T; this.next += 1){
            const at = times[this.next];
            if (kinds[this.next] !== DRUM_KICK || strengths[this.next] < MIN_STRENGTH || at - this.lastBump < MIN_GAP) continue;
            this.lastBump = at;
            amount = Math.max(amount, 0.3 + 0.7 * strengths[this.next]);
        }
        this.lastT = T;
        return amount;
    }
    reset() {
        this.list = null;
        this.key = null;
    }
    seek(T) {
        const times = this.list?.times;
        let lo = 0, hi = times?.length ?? 0;
        while(lo < hi){
            const m = lo + hi >> 1;
            if (times[m] <= T) lo = m + 1;
            else hi = m;
        }
        this.next = lo;
        this.lastT = T;
        this.lastBump = -Infinity;
    }
}
