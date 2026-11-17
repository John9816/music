// Adapted from Folia 5bdade1102f9b80830eec5f523e87f3e2a13d40d; src/components/visualizer/nebbia/nebbiaAquarium.ts
// Copyright Folia contributors. AGPL-3.0-only. See app/THIRD_PARTY_NOTICES.md.
import { NebbiaBeatCursor } from './nebbiaBeatCursor.js';
import { NebbiaJellies } from './nebbiaJellies.js';
import { NEBBIA_MAX_BURSTS, NEBBIA_MAX_JELLIES } from './types.js';
import { NebbiaWeedSway } from './nebbiaWeedSway.js';
const BURST_LIFE = 6;
const SPOT_GROW = 0.45, SPOT_ATTACK = 0.06, SPOT_DECAY = 0.25;
const rand = (n)=>{
    const x = Math.sin(n * 91.7 + 47.3) * 43758.5453;
    return x - Math.floor(x);
};
export class NebbiaAquarium {
    jellies = new NebbiaJellies();
    cursor = new NebbiaBeatCursor();
    out = {
        jelly: new Float32Array(NEBBIA_MAX_JELLIES * 4),
        jellyColor: new Float32Array(NEBBIA_MAX_JELLIES * 4),
        count: 0,
        bubbles: 0,
        sway: new Float32Array(4),
        weedIdle: 1,
        bursts: new Float32Array(NEBBIA_MAX_BURSTS * 4),
        burstCount: 0,
        beatRows: 0,
        spotScale: 1
    };
    spotKick = 0;
    spotFrom = 0;
    spotAge = 10;
    weed = new NebbiaWeedSway();
    nextBurst = 0;
    setPalette(la, lb, lc) {
        this.jellies.setPalette(la, lb, lc);
    }
    step(dt, time, aspect, tuning, beats) {
        const { out } = this;
        const hits = this.cursor.step(beats?.events ?? null, beats?.heard ?? 0);
        this.jellies.step(out, dt, time, aspect, tuning, hits, beats?.jelly ?? 0);
        out.bubbles = tuning.bubbles;
        const { sway, bursts } = out;
        for (const hit of hits){
            const weed = beats?.weed ?? 0, bubble = beats?.bubble ?? 0;
            if (weed > 0) this.weed.kick(hit.gain * weed * (hit.down ? 1 : 0.7));
            const spot = beats?.spot ?? 0;
            if (spot > 0) {
                this.spotFrom = this.spotLevel();
                this.spotKick = Math.max(this.spotFrom, Math.min(1.5, hit.gain * spot * (hit.down ? 1 : 0.7)));
                this.spotAge = 0;
            }
            if (bubble > 0) {
                const o = this.nextBurst * 4;
                bursts[o] = 0.17 + rand(hit.index) * Math.max(0, aspect - 0.34);
                bursts[o + 1] = time;
                bursts[o + 2] = Math.min(1, hit.gain * bubble * (hit.down ? 1 : 0.75));
                bursts[o + 3] = rand(hit.index * 3.3 + 1) * 100;
                this.nextBurst = (this.nextBurst + 1) % NEBBIA_MAX_BURSTS;
            }
        }
        out.beatRows = beats && beats.bubble > 0 ? 1 : 0;
        this.spotAge += dt;
        out.spotScale = 1 + SPOT_GROW * this.spotLevel();
        this.weed.step(dt, sway);
        const idle = beats && beats.weed > 0 ? 0 : 1;
        out.weedIdle += (idle - out.weedIdle) * (1 - Math.exp(-dt / 0.6));
        let n = 0;
        for(let i = 0; i < NEBBIA_MAX_BURSTS; i += 1){
            const age = time - bursts[i * 4 + 1];
            if (bursts[i * 4 + 2] > 0 && age >= 0 && age < BURST_LIFE) n = i + 1;
            else bursts[i * 4 + 2] = 0;
        }
        out.burstCount = n;
        return out;
    }
    spotLevel() {
        const a = this.spotAge;
        return a < SPOT_ATTACK ? this.spotFrom + (this.spotKick - this.spotFrom) * a / SPOT_ATTACK : this.spotKick * Math.exp(-(a - SPOT_ATTACK) / SPOT_DECAY);
    }
}
