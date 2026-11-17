// Adapted from Folia 5bdade1102f9b80830eec5f523e87f3e2a13d40d; src/components/visualizer/nebbia/nebbiaBeatCursor.ts
// Copyright Folia contributors. AGPL-3.0-only. See app/THIRD_PARTY_NOTICES.md.
const MAX_STEP = 0.5;
export class NebbiaBeatCursor {
    events = null;
    cursor = 0;
    lastT = -Infinity;
    hits = [];
    step(events, T) {
        const { hits } = this;
        hits.length = 0;
        if (!events) {
            this.events = null;
            return hits;
        }
        const jumped = events !== this.events || T < this.lastT || T - this.lastT > MAX_STEP;
        this.lastT = T;
        if (jumped) {
            this.events = events;
            let lo = 0, hi = events.length;
            while(lo < hi){
                const m = lo + hi >> 1;
                if (events[m].t <= T) lo = m + 1;
                else hi = m;
            }
            this.cursor = lo;
            return hits;
        }
        for(; this.cursor < events.length && events[this.cursor].t <= T; this.cursor += 1){
            const e = events[this.cursor];
            if (e.rhythmic === false) continue;
            hits.push({
                index: this.cursor,
                gain: Math.max(0.35, e.impact ?? 1),
                down: e.kind === 'downbeat'
            });
        }
        return hits;
    }
}
