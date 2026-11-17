// Adapted from Folia 5bdade1102f9b80830eec5f523e87f3e2a13d40d; src/components/visualizer/nebbia/nebbiaSceneClock.ts
// Copyright Folia contributors. AGPL-3.0-only. See app/THIRD_PARTY_NOTICES.md.
import { clamp } from './nebbiaConstants.js';
const SCENE_RESET = 1000;
const SCENE_WRAP = 3600;
export class NebbiaSceneClock {
    time = 0;
    last = 0;
    tick(now, paused) {
        const dt = paused ? 0 : clamp(now - this.last, 0, 0.1);
        this.time = (this.time + dt) % SCENE_WRAP;
        this.last = now;
        return dt;
    }
    songChanged() {
        if (this.time > SCENE_RESET) this.time = 0;
    }
}
