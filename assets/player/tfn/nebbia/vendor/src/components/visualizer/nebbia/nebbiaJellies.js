// Adapted from Folia 5bdade1102f9b80830eec5f523e87f3e2a13d40d; src/components/visualizer/nebbia/nebbiaJellies.ts
// Copyright Folia contributors. AGPL-3.0-only. See app/THIRD_PARTY_NOTICES.md.
import { NEBBIA_MAX_JELLIES } from './types.js';
const VIVID = [
    [
        1,
        0.35,
        0.72
    ],
    [
        0.35,
        0.8,
        1
    ],
    [
        0.72,
        0.5,
        1
    ],
    [
        1,
        0.72,
        0.35
    ]
];
const TOP = -0.35, BOTTOM = 1.35;
const OWN_WITH_BEATS = 0.4;
const WEAK_BEAT = 0.6;
const rand = (n)=>{
    const x = Math.sin(n * 127.1 + 311.7) * 43758.5453;
    return x - Math.floor(x);
};
const kickLevel = (j)=>j.kickAge < 0.07 ? j.kickFrom + (j.kick - j.kickFrom) * j.kickAge / 0.07 : j.kick * Math.exp(-(j.kickAge - 0.07) / 0.3);
const OWN_EASE = 1.5;
const spawn = (i, seed, y)=>({
        xf: rand(seed * 3.1 + i),
        y,
        depth: rand(seed * 5.7 + i * 1.3),
        rate: 1.6 + 0.9 * rand(seed * 2.3 + i),
        phase: rand(seed + i * 7.3) * Math.PI * 2,
        rise: 0.012 + 0.012 * rand(seed * 9.1 + i),
        hue: rand(seed * 4.4 + i * 11.0),
        kick: 0,
        kickFrom: 0,
        kickAge: 10,
        seed
    });
export class NebbiaJellies {
    list = Array.from({
        length: NEBBIA_MAX_JELLIES
    }, (_, i)=>spawn(i, i + 1, TOP + rand(i * 13.7) * (BOTTOM - TOP)));
    palette = [
        [
            1,
            0.81,
            0.54
        ],
        [
            0.54,
            0.8,
            1
        ],
        [
            0.8,
            0.54,
            1
        ]
    ];
    own = 1;
    setPalette(la, lb, lc) {
        this.palette = [
            la,
            lb,
            lc
        ];
    }
    step(out, dt, time, aspect, tuning, fired, strength) {
        const count = Math.round(tuning.jellies);
        const target = strength > 0 ? OWN_WITH_BEATS : 1;
        this.own += Math.sign(target - this.own) * Math.min(Math.abs(target - this.own), dt * (1 - OWN_WITH_BEATS) / OWN_EASE);
        const { own } = this;
        const { jelly, jellyColor } = out;
        for(let i = 0; i < count; i += 1){
            let j = this.list[i];
            j.phase += dt * j.rate;
            const swim = Math.max(Math.sin(j.phase), 0);
            for (const beat of fired){
                if (strength <= 0) break;
                j.kickFrom = kickLevel(j);
                j.kick = Math.max(j.kickFrom, beat.gain * strength * (beat.down ? 1 : WEAK_BEAT));
                j.kickAge = 0;
            }
            j.kickAge += dt;
            const kick = kickLevel(j);
            j.y -= dt * (j.rise * (1 + 0.9 * swim * own) + 0.06 * kick);
            if (j.y < TOP) j = this.list[i] = spawn(i, j.seed + NEBBIA_MAX_JELLIES, BOTTOM);
            const x = (j.xf + 0.02 * Math.sin(time * 0.15 + j.hue * 10)) * (aspect + 0.2) - 0.1;
            const o = i * 4;
            jelly[o] = x;
            jelly[o + 1] = j.y;
            jelly[o + 2] = (0.03 + 0.055 * j.depth) * tuning.jellySize;
            jelly[o + 3] = Math.min(1.3, Math.max(swim ** 3 * own, kick));
            const vivid = VIVID[Math.floor(j.hue * 4) % 4], theme = this.palette[Math.floor(j.hue * 3.7 % 1 * 3)];
            const shade = 0.45 + 0.55 * j.depth;
            for(let c = 0; c < 3; c += 1)jellyColor[o + c] = (vivid[c] * 0.65 + theme[c] * 0.35) * shade;
            jellyColor[o + 3] = j.phase;
        }
        out.count = count;
    }
}
