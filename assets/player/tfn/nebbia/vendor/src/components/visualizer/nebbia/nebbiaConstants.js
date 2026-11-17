// Adapted from Folia 5bdade1102f9b80830eec5f523e87f3e2a13d40d; src/components/visualizer/nebbia/nebbiaConstants.ts
// Copyright Folia contributors. AGPL-3.0-only. See app/THIRD_PARTY_NOTICES.md.
export const NEBBIA_FIXED = {
    edge: 0.6,
    beads: 0.35,
    drip: 0.25,
    refract: 1,
    glint: 1,
    fieldDrops: 0.5,
    wind: 0,
    endBead: 1,
    endBeadMin: 48,
    beadHold: 4,
    breathSpread: 1.2,
    breathHold: 1,
    breathFade: 8,
    breathThick: 0.7,
    bumpRate: 1,
    bumpFall: 0.5
};
export const MASK_SCALE = 1;
export const FOG_DIV = 4;
export const clamp = (value, min = 0, max = 1)=>Math.max(min, Math.min(max, value));
export const smooth = (t)=>t * t * (3 - 2 * t);
