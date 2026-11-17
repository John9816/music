// Adapted from Folia 5bdade1102f9b80830eec5f523e87f3e2a13d40d; src/components/visualizer/nebbia/nebbiaSnow.ts
// Copyright Folia contributors. AGPL-3.0-only. See app/THIRD_PARTY_NOTICES.md.
import { segDist } from './nebbiaSegments.js';
import { packFlakes, packIce, packInkIce } from './nebbiaSnowDraw.js';
import { NebbiaSnowFall, slantOf } from './nebbiaSnowFall.js';
import { buildFlakeAtlas, buildFlakeKind, FLAKE_FILL, FLAKE_R, FLAKE_SPRITE } from './nebbiaSnowFlakes.js';
import { NebbiaSnowWater } from './nebbiaSnowWater.js';
export const PEN_FLOATS = 5;
const KIND_TYPES = [
    'clump',
    'clump',
    'clump',
    'clump',
    'clump',
    'clump',
    'clump',
    'star',
    'star',
    'star',
    'star',
    'star'
];
const TYPE_ODDS = [
    [
        'clump',
        0.6
    ],
    [
        'star',
        1
    ]
];
const QUICK_MELT = 0.25;
const rand = (a, b)=>a + Math.random() * (b - a);
const waterOf = (r, k)=>(4 * 4.5 * Math.log(1 + r / k / 2.5) * k) ** 2;
const TAU = Math.PI * 2;
export class NebbiaSnow {
    kinds = KIND_TYPES.map(buildFlakeKind);
    beads = [
        0,
        1,
        2
    ].map((i)=>buildFlakeKind('bead', KIND_TYPES.length + i));
    byType = new Map(TYPE_ODDS.map(([type])=>[
            type,
            this.kinds.filter((k)=>k.type === type)
        ]));
    inst = new Float32Array(0);
    water = new NebbiaSnowWater();
    fall = new NebbiaSnowFall(KIND_TYPES.length);
    flakes = [];
    spawnAcc = 0;
    W = 0;
    H = 0;
    k = 1;
    clock = 0;
    wetAt = -Infinity;
    sweepBox = [
        0,
        0,
        0,
        0
    ];
    resize(W, H) {
        if (W === this.W && H === this.H) return;
        this.W = W;
        this.H = H;
        this.k = H / 1000;
        this.water.resize(W, H);
        this.fall.resize(W, H);
        this.flakes = [];
    }
    atlas() {
        const all = [
            ...this.kinds,
            ...this.beads
        ];
        const canvas = buildFlakeAtlas(all);
        for (const kind of all)kind.stages = [];
        return [
            canvas,
            all.length
        ];
    }
    step(dt, t, sweeps, wet, wind, outside = true) {
        this.fall.step(dt, outside ? t.snow : 0, wind);
        this.spawnAcc += dt * t.snow * 25 * this.W * this.H / (1280 * 720);
        for(; this.spawnAcc >= 1; this.spawnAcc -= 1)this.flakes.push(this.newFlake(t, wind));
        this.boxOf(sweeps);
        for(let i = this.flakes.length - 1; i >= 0; i -= 1){
            const f = this.flakes[i];
            const landing = f.age < f.app;
            f.age += dt;
            if (f.age < f.app) {
                f.rot += f.spin * (1 - f.age / f.app) * dt;
                continue;
            }
            if (landing && this.landsInWater(f, sweeps, wet)) f.quick = true;
            if (f.quick) f.melt = Math.min(1, f.melt + dt / QUICK_MELT);
            if (f.quick ? f.melt >= 1 : this.wiped(f, sweeps) || f.age >= f.app + f.hold && this.melt(f, dt * t.snowMelt)) {
                this.flakes[i] = this.flakes[this.flakes.length - 1];
                this.flakes.pop();
            }
        }
        this.water.step(dt);
        this.clock += dt;
        if (sweeps.length) this.water.absorb(sweeps, 0);
        if (wet.length && this.clock - this.wetAt >= 0.05) {
            this.wetAt = this.clock;
            this.water.absorb(wet, 3 * this.k);
        }
    }
    newFlake(t, wind) {
        const { k } = this;
        const u = Math.random(), type = TYPE_ODDS.find(([, p])=>u < p)[0], pool = this.byType.get(type);
        const r = (Math.random() < 0.3 ? rand(4.5, 6) : rand(2.5, 4.5)) * k * t.snowSize;
        const app = rand(2, 3.2) / (0.75 + 0.25 * wind), fall = rand(45, 75) * k * app, calm = 1 / (0.6 + 0.4 * wind);
        return {
            x: Math.random() * this.W,
            y: Math.random() * this.H,
            r,
            rot: Math.random() * TAU,
            spin: rand(-1.33, 1.33) * (0.7 + 0.3 * wind),
            kind: pool[Math.floor(Math.random() * pool.length)],
            app,
            ox: rand(-15, 15) * k - slantOf(wind) * fall,
            oy: -fall,
            curl: rand(-0.2, 0.2) * calm,
            ff: rand(1.5, 3.5),
            fa: rand(1, 4) * k * calm,
            fp: Math.random() * TAU,
            age: 0,
            hold: 0.3 + Math.random() ** 2.5 * 7,
            dur: rand(2.5, 4.5) + r / k * 0.18,
            melt: 0,
            water: 0,
            drops: null,
            quick: false
        };
    }
    melt(f, amount) {
        f.melt = Math.min(1, f.melt + amount / f.dur);
        const total = waterOf(f.r, this.k) * f.melt, delta = total - f.water;
        f.water = total;
        if (!f.drops && f.melt > 0.12) {
            f.drops = f.kind.lumps.map((l)=>{
                const [x, y] = this.lumpAt(f, l), d = this.water.spawn(x, y, Math.sqrt(Math.max(1, total * l.w)), 1, 0);
                d.pin = {
                    x,
                    y
                };
                return d;
            });
        } else if (f.drops) {
            const lumps = f.kind.lumps, drops = f.drops;
            let sw = 0;
            for(let j = 0; j < drops.length; j += 1){
                const d = drops[j];
                if (d?.dead) drops[j] = null;
                else if (d) sw += lumps[j].w;
            }
            for(let j = 0; j < drops.length; j += 1){
                const d = drops[j];
                if (d) {
                    d.mass += delta * lumps[j].w / (sw || 1);
                    this.water.grew(d);
                }
            }
        }
        if (f.melt < 1) return false;
        for (const d of f.drops ?? [])if (d) d.pin = null;
        return true;
    }
    lumpAt(f, l) {
        const s = f.r * 2 / (FLAKE_SPRITE * FLAKE_FILL) * FLAKE_R, c = Math.cos(f.rot), sn = Math.sin(f.rot);
        return [
            f.x + (l.x * c - l.y * sn) * s,
            f.y + (l.x * sn + l.y * c) * s + f.r * 0.25
        ];
    }
    landsInWater(f, sweeps, wet) {
        if (this.touches(f, sweeps) || this.touches(f, wet)) return true;
        const d = this.water.near(f.x, f.y, f.r * 0.6);
        if (d) {
            d.mass += waterOf(f.r, this.k);
            this.water.wake(d);
        }
        return d !== null;
    }
    touches(f, segs) {
        for(let p = 0; p < segs.length; p += PEN_FLOATS)if (segDist(f.x, f.y, segs, p) < segs[p + 4] / 2 + f.r * 0.6) return true;
        return false;
    }
    boxOf(segs) {
        const b = this.sweepBox;
        b[0] = b[1] = Infinity;
        b[2] = b[3] = -Infinity;
        for(let p = 0; p < segs.length; p += PEN_FLOATS){
            const hw = segs[p + 4] / 2;
            b[0] = Math.min(b[0], segs[p] - hw, segs[p + 2] - hw);
            b[1] = Math.min(b[1], segs[p + 1] - hw, segs[p + 3] - hw);
            b[2] = Math.max(b[2], segs[p] + hw, segs[p + 2] + hw);
            b[3] = Math.max(b[3], segs[p + 1] + hw, segs[p + 3] + hw);
        }
    }
    wiped(f, sweeps) {
        const b = this.sweepBox, m = f.r * 0.6;
        if (f.x + m < b[0] || f.x - m > b[2] || f.y + m < b[1] || f.y - m > b[3]) return false;
        for(let p = 0; p < sweeps.length; p += PEN_FLOATS){
            if (segDist(f.x, f.y, sweeps, p) > sweeps[p + 4] / 2 + f.r * 0.6) continue;
            for (const d of f.drops ?? [])if (d) this.water.kill(d);
            return true;
        }
        return false;
    }
    drawFog(ctx, t) {
        this.water.drawFog(ctx, t.hold, t.refog);
    }
    instances(out) {
        return this.water.instances(out);
    }
    get changed() {
        return this.water.changed;
    }
    flakeInstances(inkIce = []) {
        const n = this.fall.count;
        this.inst = packFlakes(this.flakes, this.inst, n);
        this.fall.pack(this.inst, this.clock);
        let count = n + this.flakes.length, more;
        [this.inst, more] = packIce(this.water.drops, (d)=>this.water.sizeX(d) / 4, this.beads, this.inst, count);
        count += more;
        [this.inst, more] = packInkIce(inkIce, this.beads, this.inst, count);
        return [
            this.inst,
            count + more
        ];
    }
}
