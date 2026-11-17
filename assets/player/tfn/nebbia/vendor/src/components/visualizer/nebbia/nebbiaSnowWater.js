// Adapted from Folia 5bdade1102f9b80830eec5f523e87f3e2a13d40d; src/components/visualizer/nebbia/nebbiaSnowWater.ts
// Copyright Folia contributors. AGPL-3.0-only. See app/THIRD_PARTY_NOTICES.md.
import { NebbiaSnowGrid } from './nebbiaSnowGrid.js';
import { NebbiaSnowTrails } from './nebbiaSnowTrails.js';
export const iceParams = {
    freezeAfter: 1.5,
    freezeDur: 3,
    slide: 3,
    minR: 2.5,
    grow: 0.75,
    spinR: 7.5,
    spin: 0.35,
    maxIce: 200,
    off: false
};
const SLIDE_AT = 0.3;
export const iceSizeScale = (r, k)=>1 + Math.log(Math.max(1, r / (Math.max(0.5, iceParams.minR) * k)));
const SPECKS_PER_ICE = 1.5;
const rand = (a, b)=>a + Math.random() * (b - a);
const FIELD_EVERY = 0.05;
export class NebbiaSnowWater {
    drops = [];
    trails = new NebbiaSnowTrails();
    woken = [];
    changed = true;
    urgent = true;
    fieldAt = -Infinity;
    maxR = 40;
    grid = new NebbiaSnowGrid();
    W = 1;
    H = 1;
    k = 1;
    time = 0;
    specks = 0;
    frozen = 0;
    slip = 0;
    stick = 1600;
    evapTau = 150;
    evapEdge = 2.6;
    maxSize = 72;
    resize(W, H) {
        if (W === this.W && H === this.H) return;
        this.W = W;
        this.H = H;
        this.k = H / 1000;
        this.grid.reset(W, H, 70 * this.k * 0.3);
        this.drops.length = 0;
        this.trails.clear();
        this.woken = [];
        this.urgent = true;
        this.maxR = 40 * this.k;
    }
    spawn(x, y, size, density = 1, spread = 0.5) {
        const d = {
            x,
            y,
            vx: 0,
            vy: 0,
            mass: (size * density) ** 2,
            density,
            sx: spread,
            sy: spread,
            resist: 0,
            shift: 0,
            nextMotion: 0,
            lastTx: x,
            lastTy: y,
            nextTrail: rand(20, 30) * this.k,
            parent: null,
            dead: false,
            pin: null,
            wipe: null,
            awake: false,
            cell: -1,
            wokeMass: 0,
            wokeX: 0,
            wokeY: 0,
            still: 0,
            ice: 0,
            iceV: 1,
            iceDur: 1,
            rot: Math.random() * Math.PI * 2,
            speck: false,
            slid: 0,
            tilt: 0
        };
        this.drops.push(d);
        this.grid.place(d);
        this.wake(d);
        return d;
    }
    wake(d) {
        if (!d.awake && !d.dead) {
            d.awake = true;
            d.wokeMass = d.mass;
            d.wokeX = d.x;
            d.wokeY = d.y;
            this.woken.push(d);
        }
    }
    grew(d) {
        if (d.mass > d.wokeMass * 1.05) this.wake(d);
    }
    kill(d) {
        d.dead = true;
        this.urgent = true;
    }
    size(d) {
        return [
            this.sizeX(d),
            (d.sy + 1) * Math.sqrt(Math.max(0, d.mass)) / d.density
        ];
    }
    sizeX(d) {
        return (d.sx + 1) * Math.sqrt(Math.max(0, d.mass)) / d.density;
    }
    step(dt) {
        if (dt <= 0) return;
        this.time += dt;
        const spread = 0.01 ** dt;
        for(let i = 0; i < this.drops.length; i += 1)if (!this.drops[i].dead) this.move(this.drops[i], dt, spread);
        this.collide();
        let specks = 0, frozen = 0;
        for (const d of this.drops){
            if (d.speck) specks += 1;
            else if (d.ice > 0) frozen += 1;
        }
        this.specks = specks;
        this.frozen = frozen;
        for(let i = this.drops.length - 1; i >= 0; i -= 1){
            const d = this.drops[i];
            if (!d.dead) continue;
            this.endWipe(d);
            this.grid.unplace(d);
            this.drops[i] = this.drops[this.drops.length - 1];
            this.drops.pop();
        }
    }
    move(d, dt, spread) {
        const k = this.k;
        d.mass = Math.min(d.mass, this.massCap(d));
        d.mass -= (this.evapEdge * k * Math.sqrt(Math.max(0, d.mass)) + d.mass / this.evapTau) * dt * (1 - 0.85 * d.ice);
        if (d.mass <= 0) {
            d.dead = true;
            return;
        }
        d.sx *= spread;
        d.sy *= spread;
        if (d.pin) {
            d.x = d.pin.x;
            d.y = d.pin.y;
            d.vx = d.vy = 0;
            d.still = 0;
            return;
        }
        if (this.freeze(d, dt)) return;
        if (d.vy === 0 && d.mass < this.stick * k * k) {
            if (d.wipe) this.endWipe(d);
            return;
        }
        if (this.time >= d.nextMotion) {
            d.nextMotion = this.time + rand(0.1, 0.4);
            const maxResist = (30 + 40 * (1 - this.slip)) ** 2 * k * k * 4;
            d.resist = Math.random() * 2400 * k * maxResist;
            d.shift = Math.random() * rand(0, 0.1);
            if (d.mass < this.stick * k * k) d.resist = Math.max(d.resist, 2 * 2400 * k * d.mass);
        }
        const acc = (2400 * k * d.mass - d.resist) / d.mass;
        d.vy = Math.max(0, d.vy + acc * dt);
        d.vx = d.vy * d.shift;
        d.x += d.vx * dt;
        d.y += d.vy * dt;
        d.sy = Math.max(d.sy, 0.3 * 2 * Math.atan(d.vy * 0.005) / Math.PI);
        if (d.y > this.H + 100) {
            d.dead = true;
            return;
        }
        this.grid.place(d);
        if (d.vy > 8 * k) {
            d.wipe = this.trails.track(d.wipe, d.x, d.y, this.sizeX(d) * 0.3);
            this.wake(d);
            this.urgent = true;
        } else this.endWipe(d);
        if (Math.hypot(d.x - d.lastTx, d.y - d.lastTy) > d.nextTrail) this.split(d);
    }
    freeze(d, dt) {
        const p = iceParams, k = this.k;
        if (d.speck) {
            d.ice = 1;
            return true;
        }
        if (d.ice === 0) {
            if (p.off || d.vy > 0 || this.sizeX(d) / 4 < p.minR * k) {
                d.still = 0;
                return false;
            }
            d.still += dt;
            const scale = iceSizeScale(this.sizeX(d) / 4, k);
            if (d.still < p.freezeAfter * scale || this.frozen >= p.maxIce) return false;
            this.frozen += 1;
            d.ice = 1e-3;
            d.iceV = rand(0.65, 1.35);
            d.iceDur = Math.max(1, p.freezeDur * scale);
        }
        if (d.ice < 1) d.mass = Math.min(this.massCap(d), d.mass * Math.max(0.25, p.grow) ** (2 * dt / d.iceDur));
        d.ice = Math.min(1, d.ice + dt / d.iceDur);
        if (d.ice < SLIDE_AT) {
            d.vx = d.vy = 0;
            return true;
        }
        const v = p.slide * k * d.iceV * Math.min(1, (d.ice - SLIDE_AT) / 0.15);
        d.vy += (v - d.vy) * Math.min(1, dt * 2);
        d.vx = Math.sin(this.time * 0.7 + d.rot * 5) * d.vy * 0.15;
        d.x += d.vx * dt;
        d.y += d.vy * dt;
        if (d.y > this.H + 100) {
            d.dead = true;
            return true;
        }
        d.slid += d.vy * dt;
        const over = this.sizeX(d) / 4 / k - p.spinR;
        const amp = over > 0 ? p.spin * Math.min(1, over / 6) : 0;
        d.tilt += (amp * Math.sin(d.slid / (14 * k) + d.rot * 3) - d.tilt) * Math.min(1, dt * 3);
        this.grid.place(d);
        if (Math.abs(d.x - d.wokeX) + Math.abs(d.y - d.wokeY) > k) this.wake(d);
        else this.grew(d);
        if (d.vy * FIELD_EVERY > 0.25 * k) this.urgent = true;
        if (Math.hypot(d.x - d.lastTx, d.y - d.lastTy) > d.nextTrail && d.mass > 300 * k * k && this.specks < p.maxIce * SPECKS_PER_ICE) {
            const t = this.spawn(d.x + rand(-1.5, 1.5) * k, d.y - this.sizeX(d) / 4, this.sizeX(d) * rand(0.18, 0.3), 1, 0);
            t.speck = true;
            t.ice = 1;
            t.parent = d;
            d.mass -= t.mass;
            d.lastTx = d.x;
            d.lastTy = d.y;
            d.nextTrail = rand(10, 18) * k;
            this.specks += 1;
        }
        return true;
    }
    split(d) {
        if (d.mass < 1000 * this.k * this.k) return;
        const [w, h] = this.size(d);
        const t = this.spawn(d.x + rand(-5, 5) * this.k, d.y - h / 4, w * rand(0.3, 0.5), 0.2, 0);
        t.sx = 0.1;
        t.sy = d.vy * 0.01 * 0.6;
        t.parent = d;
        d.mass -= t.mass;
        d.lastTx = d.x;
        d.lastTy = d.y;
        d.nextTrail = rand(20, 30) * this.k;
    }
    endWipe(d) {
        if (d.wipe && d.wipe.end === null) d.wipe.end = this.time;
        d.wipe = null;
    }
    collide() {
        const { cells, gw, gh, size: cell } = this.grid, list = this.woken;
        this.woken = [];
        for (const d of list){
            d.awake = false;
            if (d.dead) continue;
            const cx = Math.floor(d.x / cell), cy = Math.floor(d.y / cell), md = this.mergeDistance(d);
            for(let gy = cy - 1; gy <= cy + 1; gy += 1)for(let gx = cx - 1; gx <= cx + 1; gx += 1){
                if (gx < 0 || gy < 0 || gx >= gw || gy >= gh) continue;
                for (const o of cells[gx + gy * gw]){
                    if (o === d || o.dead || o.parent === d || d.parent === o || d.parent && d.parent === o.parent) continue;
                    if (Math.hypot(d.x - o.x, d.y - o.y) >= md + this.mergeDistance(o)) continue;
                    const [big, small] = d.mass >= o.mass ? [
                        d,
                        o
                    ] : [
                        o,
                        d
                    ];
                    const m = big.mass + small.mass;
                    big.vx = (big.vx * big.mass + small.vx * small.mass) / m;
                    big.vy = (big.vy * big.mass + small.vy * small.mass) / m;
                    big.density = (big.density * big.mass + small.density * small.mass) / m;
                    big.mass = Math.min(m, this.massCap(big));
                    big.ice = big.ice > 0 ? (big.ice * (m - small.mass) + small.ice * small.mass) / m : 0;
                    if (big.ice < 1e-3) big.ice = 0;
                    big.speck = big.speck && small.speck;
                    small.dead = true;
                    this.urgent = true;
                    this.wake(big);
                    if (small === d) break;
                }
                if (d.dead) break;
            }
        }
    }
    absorb(segs, pad) {
        this.grid.alongSegments(segs, pad, this.maxR, (d)=>this.sizeX(d) / 4, (d)=>this.kill(d));
    }
    near(x, y, extra) {
        return this.grid.at(x, y, extra, (d)=>this.sizeX(d) / 4);
    }
    massCap(d) {
        return (this.maxSize * this.k * d.density) ** 2;
    }
    mergeDistance(d) {
        return this.sizeX(d) * (1 + d.sx) * 0.16;
    }
    drawFog(ctx, hold, refog) {
        this.trails.draw(ctx, this.time, hold, refog);
    }
    instances(out) {
        this.changed = this.urgent || this.time - this.fieldAt >= FIELD_EVERY;
        if (!this.changed) return out;
        this.urgent = false;
        this.fieldAt = this.time;
        out.length = 0;
        let maxR = 0;
        for (const d of this.drops){
            const s = Math.sqrt(Math.max(0, d.mass)) / d.density, w = (d.sx + 1) * s, h = (d.sy + 1) * s;
            if (w < 2 || d.dead) continue;
            out.push(d.x, d.y, w * 2, h * 2, w / 50, 1);
            maxR = Math.max(maxR, w / 4);
        }
        this.maxR = maxR + 2 * this.k;
        return out;
    }
}
