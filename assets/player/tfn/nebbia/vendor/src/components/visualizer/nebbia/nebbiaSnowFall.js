// Adapted from Folia 5bdade1102f9b80830eec5f523e87f3e2a13d40d; src/components/visualizer/nebbia/nebbiaSnowFall.ts
// Copyright Folia contributors. AGPL-3.0-only. See app/THIRD_PARTY_NOTICES.md.
import { FLAKE_FLOATS } from './nebbiaSnowGl.js';
const LAYERS = [
    {
        n: 240,
        r: [
            0.9,
            1.7
        ],
        vy: [
            45,
            75
        ],
        alpha: 0.3,
        p: 0.2,
        sway: [
            1,
            3
        ]
    },
    {
        n: 70,
        r: [
            2,
            3.2
        ],
        vy: [
            95,
            140
        ],
        alpha: 0.5,
        p: 0.55,
        sway: [
            2,
            5
        ]
    }
];
const rand = (a, b)=>a + Math.random() * (b - a);
const gustOf = (wind)=>wind * (1 + 0.5 * (wind - 1));
export const slantOf = (wind)=>-0.45 * Math.max(0, gustOf(wind));
export class NebbiaSnowFall {
    rows;
    layers = LAYERS.map(()=>[]);
    W = 0;
    H = 0;
    k = 1;
    constructor(rows){
        this.rows = rows;
    }
    resize(W, H) {
        this.W = W;
        this.H = H;
        this.k = H / 1000;
        for (const l of this.layers)l.length = 0;
    }
    get count() {
        return this.layers[0].length + this.layers[1].length;
    }
    step(dt, amount, wind) {
        const { W, H, k } = this, slant = slantOf(wind), area = W * H / (1280 * 720);
        LAYERS.forEach((spec, li)=>{
            const list = this.layers[li], want = Math.round(spec.n * amount * area);
            while(list.length < want)list.push(this.make(li, Math.random() * H));
            if (list.length > want) list.length = want;
            const m = 20 * k;
            for (const f of list){
                f.y += f.vy * dt;
                f.x += f.vy * slant * dt;
                f.rot += f.spin * dt;
                if (f.y > H + m) Object.assign(f, this.make(li, -m));
                if (f.x < -m) f.x += W + 2 * m;
                else if (f.x > W + m) f.x -= W + 2 * m;
            }
        });
    }
    make(li, y) {
        const spec = LAYERS[li], k = this.k;
        return {
            x: Math.random() * this.W,
            y,
            r: rand(spec.r[0], spec.r[1]) * k,
            rot: Math.random() * Math.PI * 2,
            spin: rand(-0.6, 0.6),
            row: Math.floor(Math.random() * this.rows),
            vy: rand(spec.vy[0], spec.vy[1]) * k,
            sa: rand(spec.sway[0], spec.sway[1]) * k,
            sf: rand(0.8, 1.6),
            sp: Math.random() * Math.PI * 2
        };
    }
    pack(out, t) {
        let o = 0;
        LAYERS.forEach((spec, li)=>{
            for (const f of this.layers[li]){
                out[o] = f.x + Math.sin(t * f.sf + f.sp) * f.sa;
                out[o + 1] = f.y;
                out[o + 2] = f.r;
                out[o + 3] = f.rot;
                out[o + 4] = 0;
                out[o + 5] = f.row;
                out[o + 6] = spec.alpha;
                out[o + 7] = spec.p;
                out[o + 8] = 1;
                out[o + 9] = 1;
                o += FLAKE_FLOATS;
            }
        });
    }
}
