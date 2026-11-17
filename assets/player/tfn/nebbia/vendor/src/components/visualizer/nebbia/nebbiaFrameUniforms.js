// Adapted from Folia 5bdade1102f9b80830eec5f523e87f3e2a13d40d; src/components/visualizer/nebbia/nebbiaFrameUniforms.ts
// Copyright Folia contributors. AGPL-3.0-only. See app/THIRD_PARTY_NOTICES.md.
import { NEBBIA_FIXED } from './nebbiaConstants.js';
const SCENERY_BITS = {
    buildings: 1,
    lights: 2,
    cars: 4,
    road: 8
};
const RAIN_BITS = {
    slant: 16 | 32,
    straight: 16,
    off: 0
};
export const nebbiaFrameUniforms = (t, [sx, sy], spot, W, H, time, aqua = null)=>{
    const asp = W / H;
    const srcY = aqua ? -0.04 : 0.595;
    return {
        time,
        mist: t.mist,
        edge: NEBBIA_FIXED.edge,
        refract: NEBBIA_FIXED.refract,
        bus: t.busSpeed,
        glint: NEBBIA_FIXED.glint,
        neon: t.neon,
        glassShift: [
            -sx * 0.35 / W,
            -sy * 0.35 / H
        ],
        sceneShift: [
            -sx / W,
            -sy / H
        ],
        spotSrc: [
            t.spotX * asp,
            srcY
        ],
        spotSrc2: [
            (1 - t.spotX) * asp,
            srcY
        ],
        spotTgt: [
            spot.x / W * asp,
            spot.y / H
        ],
        spotR: Math.max(0.02, spot.r / H * 0.75) * (aqua?.spotScale ?? 1),
        spotI: t.scenery.includes('spot') ? spot.i * t.spot : 0,
        scenery: t.scenery.reduce((bits, part)=>bits | (SCENERY_BITS[part] ?? 0), t.glass === 'snow' && !aqua ? 0 : RAIN_BITS[t.rain]),
        dewGlint: t.dewGlint,
        aqua
    };
};
