// Adapted from Folia 5bdade1102f9b80830eec5f523e87f3e2a13d40d; src/components/visualizer/nebbia/nebbiaWeedSway.ts
// Copyright Folia contributors. AGPL-3.0-only. See app/THIRD_PARTY_NOTICES.md.
const OMEGA = 2 * Math.PI * 2;
const DAMP = 2 * 0.3 * OMEGA;
const KICK_V = OMEGA * 1.25;
const STEP = 1 / 120;
const SPACING = 6;
const HISTORY = SPACING * 3 + 1;
export class NebbiaWeedSway {
    x = 0;
    v = 0;
    side = 1;
    carry = 0;
    history = new Float32Array(HISTORY);
    head = 0;
    kick(amount) {
        this.side = -this.side;
        this.v = this.side * amount * KICK_V;
    }
    step(dt, out) {
        this.carry += Math.min(dt, 0.1);
        while(this.carry >= STEP){
            this.carry -= STEP;
            this.v += (-OMEGA * OMEGA * this.x - DAMP * this.v) * STEP;
            this.x += this.v * STEP;
            this.head = (this.head + 1) % HISTORY;
            this.history[this.head] = this.x;
        }
        for(let k = 0; k < 4; k += 1)out[k] = this.history[(this.head - k * SPACING + HISTORY * 2) % HISTORY];
    }
}
