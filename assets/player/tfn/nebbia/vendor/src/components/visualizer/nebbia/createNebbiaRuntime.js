// Adapted from Folia 5bdade1102f9b80830eec5f523e87f3e2a13d40d; src/components/visualizer/nebbia/createNebbiaRuntime.ts
// Copyright Folia contributors. AGPL-3.0-only. See app/THIRD_PARTY_NOTICES.md.
import { TfnLyricViewport, tfnProjectLyric } from '../../../../../lyric_viewport.js';
import { resolveLyricPixelRatio } from '../../../utils/lyricRenderQuality.js';
import { loadLucideIcons, resolveLucideIconNames } from '../../../services/lucideIconResolver.js';
import { resolveThemeFontStack, resolveThemeFontWeight } from '../../../utils/fontStacks.js';
import { buildNebbiaLines, collectEmojiIcons, NEBBIA_DEFAULT_DOODLES } from './nebbiaChars.js';
import { appendNebbiaCredits } from './nebbiaCredits.js';
import { NEBBIA_FIXED } from './nebbiaConstants.js';
import { NebbiaGlassMotion } from './nebbiaDrops.js';
import { NebbiaGl } from './nebbiaGl.js';
import { NebbiaGlyphCache } from './nebbiaGlyphs.js';
import { NebbiaHits, VocalEnergy } from './nebbiaHits.js';
import { NebbiaMask } from './nebbiaMask.js';
import { resolveNebbiaPalette } from './nebbiaPalette.js';
import { buildNebbiaScene } from './nebbiaScene.js';
import { NebbiaSpot } from './nebbiaSpot.js';
import { loadNebbiaStrokes } from './nebbiaStrokes.js';
import { hashVisualizerSeed } from '../visualizerSeedHash.js';
import { NebbiaDrizzleRide } from './nebbiaDrizzleRide.js';
import { nebbiaFrameUniforms } from './nebbiaFrameUniforms.js';
import { NebbiaSceneClock } from './nebbiaSceneClock.js';
import { NebbiaCondensation } from './nebbiaCondensation.js';
import { NebbiaSnow } from './nebbiaSnow.js';
import { NebbiaFireflies } from './nebbiaFireflies.js';
import { NebbiaAquarium } from './nebbiaAquarium.js';
import { BEAT_EFFECT_IDS, beatEffectPartId } from '../../../services/beatFx/beatEffects.js';
import { getBeatEffectStrength, getBeatFxEvents, getBeatFxHeard, isBeatEffectPlaying, isBeatFxReady } from '../../../services/beatFx/beatFxLive.js';
const AQUA_BEAT = BEAT_EFFECT_IDS.nebbiaAquaBeat;
const AQUA_JELLY = beatEffectPartId(AQUA_BEAT, 'jelly'), AQUA_WEED = beatEffectPartId(AQUA_BEAT, 'weed'), AQUA_BUBBLE = beatEffectPartId(AQUA_BEAT, 'bubble');
const AQUA_SPOT = beatEffectPartId(AQUA_BEAT, 'spot');
const LAYOUT_KEYS = [
    'appear',
    'fade',
    'layouts',
    'credits',
    'jitter',
    'warp',
    'hold',
    'refog',
    'writeSpeed',
    'doodle'
];
const sameValue = (a, b)=>Array.isArray(a) && Array.isArray(b) ? a.join() === b.join() : a === b;
export class NebbiaRuntime {
    tfnActive = true;
    tfnMaxFps = 60;
    tfnPixelRatioCap = 2;
    tfnLastFrameAt = -Infinity;
    setTfnPerformance(maxFps, pixelRatioCap) {
        this.tfnMaxFps = Math.max(15, Math.min(60, maxFps));
        if (this.tfnPixelRatioCap !== pixelRatioCap) {
            this.tfnPixelRatioCap = pixelRatioCap;
            this.resize();
        }
    }
    setTfnActive(active) {
        if (this.tfnActive === active) return;
        this.tfnActive = active;
        if (active) this.requestFrame();
        else { cancelAnimationFrame(this.raf); this.raf = 0; }
    }
    tfnViewport = new TfnLyricViewport();
    tfnBaseInsets = { top: 0, bottom: 0 };
    tfnGlyphGroups = [];
    tfnInsets = { top: 0, bottom: 0 };
    setTfnInsets(top, bottom, animate = true) {
        this.tfnViewport.set(top, bottom, animate);
        this.tfnInsets = { top, bottom };
        this.requestFrame();
    }
    tfnCaptureGlyphs() {
        this.tfnBaseInsets = { ...this.tfnInsets };
        this.tfnGlyphGroups = this.laid.map(line => {
            const chars = line.chars.map(ch => ({ ch, x: ch.x, y: ch.y, s: ch.s }));
            const cx = chars.reduce((sum, c) => sum+c.x, 0)/Math.max(1,chars.length);
            const cy = chars.reduce((sum, c) => sum+c.y, 0)/Math.max(1,chars.length);
            return { chars, cx, cy };
        });
    }
    tfnMoveGlyphs() {
        if (this.still || !this.tfnActive) this.tfnViewport.finish();
        const viewport = this.tfnViewport.sample();
        if (!viewport) return;
        for (const {chars,cx,cy} of this.tfnGlyphGroups) {
            const mapped = tfnProjectLyric(cy, this.H, this.tfnBaseInsets, viewport);
            for (const c of chars) {
                c.ch.x = cx+(c.x-cx)*mapped.scale;
                c.ch.y = mapped.y+(c.y-cy)*mapped.scale;
                c.ch.s = c.s*mapped.scale;
            }
        }
    }
    input;
    canvas = document.createElement('canvas');
    gl;
    mask = new NebbiaMask();
    motion = new NebbiaGlassMotion();
    spot = new NebbiaSpot();
    energy = new VocalEnergy();
    fieldInst = [];
    condensation;
    snow = null;
    fireflies;
    observer = null;
    glyphs;
    hits = new NebbiaHits(0);
    laid = [];
    words = [];
    vocalEnv = null;
    drizzleRide = new NebbiaDrizzleRide();
    clock = new NebbiaSceneClock();
    aquarium;
    aquaBeatsOut = {
        events: [],
        heard: 0,
        jelly: 0,
        weed: 0,
        bubble: 0,
        spot: 0
    };
    song = {
        lines: [],
        seed: 'nebbia'
    };
    theme;
    tuning;
    fontScale = 1;
    renderScale;
    showText = true;
    paused = false;
    still = false;
    W = 0;
    H = 0;
    raf = 0;
    buildToken = 0;
    firstDrawn = false;
    dead = false;
    fontReady = true;
    startedAt = performance.now();
    shadersLogged = false;
    constructor(input, theme, tuning, renderScale = 1){
        this.input = input;
        this.theme = theme;
        this.tuning = tuning;
        this.renderScale = renderScale;
        this.aquarium = input.scene === 'aquarium' ? new NebbiaAquarium() : null;
        this.condensation = input.glass === 'dew' ? new NebbiaCondensation() : null;
        this.fireflies = input.glass === 'dew' ? new NebbiaFireflies() : null;
        if (input.glass !== 'rain') {
            this.mask.sweeps = [];
            this.mask.wet = [];
        }
        if (input.glass === 'snow') this.mask.ice = [];
        this.motion.bump = tuning.bump;
        this.canvas.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;display:block';
        this.glyphs = new NebbiaGlyphCache(resolveThemeFontStack(theme), resolveThemeFontWeight(theme, 600));
        input.host.appendChild(this.canvas);
        try {
            this.gl = new NebbiaGl(this.canvas, input.seeThrough, input.scene, input.glass);
            this.gl.onSpriteReady = ()=>this.requestFrame();
            if (input.glass === 'snow') {
                this.snow = new NebbiaSnow();
                this.gl.setFlakeAtlas(...this.snow.atlas());
            }
            this.canvas.addEventListener('webglcontextlost', this.handleContextLost);
            this.canvas.addEventListener('webglcontextrestored', this.handleContextRestored);
            this.observer = new ResizeObserver(()=>this.resize());
            this.observer.observe(input.host);
            this.applyTheme();
            this.resize();
        } catch (error) {
            this.dead = true;
            this.observer?.disconnect();
            this.canvas.removeEventListener('webglcontextlost', this.handleContextLost);
            this.canvas.removeEventListener('webglcontextrestored', this.handleContextRestored);
            this.canvas.getContext('webgl2')?.getExtension('WEBGL_lose_context')?.loseContext();
            this.canvas.remove();
            throw error;
        }
        this.fontReady = this.glyphs.fontReady();
        document.fonts?.addEventListener('loadingdone', this.handleFontsLoaded);
        void loadNebbiaStrokes().then((data)=>{
            if (data && !this.dead) {
                this.glyphs.clear();
                this.rebuild();
            }
        });
    }
    renderedSong = null;
    setSong(song) {
        this.song = song;
        this.rebuild();
    }
    setFontScale(scale) {
        if (scale !== this.fontScale) {
            this.fontScale = scale;
            this.rebuild();
        }
    }
    setShowText(show) {
        if (show !== this.showText) {
            this.showText = show;
            this.rebuild();
        }
    }
    setDaylight(daylight) {
        this.gl.mistTint = daylight ? [
            0.86,
            0.89,
            0.92
        ] : [
            0.07,
            0.08,
            0.1
        ];
        this.requestFrame();
    }
    setTheme(theme) {
        const iconsChanged = String(resolveLucideIconNames(theme.lyricsIcons)) !== String(resolveLucideIconNames(this.theme.lyricsIcons));
        this.theme = theme;
        const fontChanged = this.glyphs.setFont(resolveThemeFontStack(theme), resolveThemeFontWeight(theme, 600));
        if (fontChanged) this.fontReady = this.glyphs.fontReady();
        this.applyTheme();
        if (fontChanged || iconsChanged) this.rebuild();
        else this.requestFrame();
    }
    setTuning(tuning) {
        const prev = this.tuning;
        this.tuning = tuning;
        this.motion.bump = tuning.bump;
        if (LAYOUT_KEYS.some((k)=>!sameValue(prev[k], tuning[k]))) this.rebuild();
        this.requestFrame();
    }
    setRenderScale(scale) {
        if (scale === this.renderScale) return;
        this.renderScale = scale;
        this.resize();
    }
    setPlayback(paused, still) {
        if (this.paused === paused && this.still === still) return;
        this.paused = paused;
        this.still = still;
        this.requestFrame();
    }
    requestFrame() {
        if (this.tfnActive && !this.raf && !this.dead) this.raf = requestAnimationFrame(this.frame);
    }
    destroy() {
        this.dead = true;
        cancelAnimationFrame(this.raf);
        this.observer?.disconnect();
        document.fonts?.removeEventListener('loadingdone', this.handleFontsLoaded);
        this.canvas.removeEventListener('webglcontextlost', this.handleContextLost);
        this.canvas.removeEventListener('webglcontextrestored', this.handleContextRestored);
        this.gl.destroy();
        this.canvas.remove();
    }
    handleContextLost = (event)=>{
        event.preventDefault();
        cancelAnimationFrame(this.raf);
        this.dead = true;
        this.input.onFailed();
    };
    handleContextRestored = ()=>{
        this.input.onRestored();
    };
    handleFontsLoaded = ()=>{
        if (this.dead) return;
        const ready = this.glyphs.fontReady();
        const arrived = ready && !this.fontReady;
        this.fontReady = ready;
        if (!arrived) return;
        this.glyphs.clear();
        this.rebuild();
    };
    applyTheme() {
        const p = resolveNebbiaPalette(this.theme);
        this.gl.setPalette(p.sky0, p.sky1, p.la, p.lb, p.lc);
        this.aquarium?.setPalette(p.la, p.lb, p.lc);
        this.fireflies?.setPalette(p.la, p.lb, p.lc);
    }
    aquaBeats() {
        if (this.still || !isBeatFxReady() || !isBeatEffectPlaying(AQUA_BEAT)) return null;
        const heard = getBeatFxHeard().time;
        if (heard === null) return null;
        const out = this.aquaBeatsOut;
        out.events = getBeatFxEvents();
        out.heard = heard;
        out.jelly = getBeatEffectStrength(AQUA_JELLY);
        out.weed = getBeatEffectStrength(AQUA_WEED);
        out.bubble = getBeatEffectStrength(AQUA_BUBBLE);
        out.spot = getBeatEffectStrength(AQUA_SPOT);
        return out;
    }
    resize() {
        const { clientWidth: width, clientHeight: height } = this.input.host;
        if (width < 1 || height < 1) return;
        const sized = width !== this.W || height !== this.H;
        this.W = width;
        this.H = height;
        const dpr = resolveLyricPixelRatio(Math.min(this.tfnPixelRatioCap, window.devicePixelRatio || 1), this.renderScale);
        this.gl.resize(this.W, this.H, dpr);
        this.mask.resize(this.W, this.H);
        this.snow?.resize(this.W, this.H);
        this.fireflies?.resize(this.W, this.H);
        if (sized) {
            if (this.condensation) this.condensation.build(this.W, this.H);
            else if (!this.snow) this.motion.buildField(this.W, this.H);
            this.rebuild();
        }
        this.requestFrame();
    }
    rebuild() {
        const token = ++this.buildToken;
        const song = this.song;
        const { lines, seed, title, artist } = song;
        const themeIcons = resolveLucideIconNames(this.theme.lyricsIcons);
        const doodles = themeIcons.length ? themeIcons : NEBBIA_DEFAULT_DOODLES;
        void loadLucideIcons([
            ...doodles,
            ...collectEmojiIcons(lines)
        ]).catch(()=>undefined).then(()=>{
            if (token !== this.buildToken || this.dead || !this.W) return;
            if ((song.trackIdentity ?? seed) !== (this.renderedSong?.trackIdentity ?? this.renderedSong?.seed)) {
                this.clock.songChanged();
                if (song.mixHandoff && this.renderedSong && !this.paused && !this.still && this.tfnActive) {
                    this.mask.retainLyrics(performance.now() / 1000);
                }
            }
            this.renderedSong = song;
            const source = this.showText ? appendNebbiaCredits(buildNebbiaLines(lines, seed, this.tuning.doodle, doodles), this.tuning.credits ? title : null, artist) : [];
            this.laid = buildNebbiaScene(source, this.glyphs, this.tuning, {
                W: this.W,
                H: Math.max(120, this.H - this.tfnInsets.top - this.tfnInsets.bottom),
                fontScale: this.fontScale
            }, seed);
            for (const line of this.laid) for (const ch of line.chars) ch.y += this.tfnInsets.top;
            this.tfnCaptureGlyphs();
            this.hits = new NebbiaHits(hashVisualizerSeed(String(seed)));
            this.words = source.map((l)=>l.words);
            this.rebuildHits();
            this.spot.reset();
            this.requestFrame();
        });
    }
    rebuildHits() {
        this.hits.buildBig(this.laid, this.words, this.W, this.H, this.vocalEnv);
    }
    shadersReady() {
        try {
            if (this.gl.ready) {
                if (!this.shadersLogged) {
                    this.shadersLogged = true;
                    console.info(`[Nebbia] shaders ready ${Math.round(performance.now() - this.startedAt)} ms after start`);
                }
                return true;
            }
        } catch (error) {
            console.warn('[Nebbia] shaders failed to build', error);
            this.dead = true;
            this.input.onFailed();
            return false;
        }
        this.raf = requestAnimationFrame(this.frame);
        return false;
    }
    frame = ()=>{
        this.raf = 0;
        if (!this.tfnActive || this.dead || this.gl.isContextLost || !this.shadersReady()) return;
        const frameAt = performance.now();
        if (!this.paused && !this.still && frameAt - this.tfnLastFrameAt < 1000 / this.tfnMaxFps - 1) {
            this.raf = requestAnimationFrame(this.frame);
            return;
        }
        this.tfnLastFrameAt = frameAt;
        if (!this.W || !this.H) return;
        const now = performance.now() / 1000;
        const frozen = this.paused || this.still;
        const dt = this.clock.tick(now, this.paused);
        const T = this.renderedSong?.currentTime?.get() ?? this.input.currentTime.get();
        const t = this.tuning;
        const ride = this.drizzleRide;
        const rainGlass = this.input.glass === 'rain';
        if (rainGlass || !this.aquarium) ride.step(this.motion, now, T, frozen, t.bump, !this.aquarium);
        else this.motion.beginFrame(now, frozen, false);
        const vocalStrength = rainGlass ? ride.rain : 0;
        if (rainGlass && ride.env !== this.vocalEnv) {
            this.vocalEnv = ride.env;
            this.rebuildHits();
        }
        const e = this.energy.update(this.input.vocal.get(), Math.max(dt, 1 / 60));
        this.hits.advance(T, e, this.still ? 0 : t.rainHit * vocalStrength, NebbiaHits.lifeOf(t.refog, NEBBIA_FIXED.beadHold), this.W, this.H);
        this.tfnMoveGlyphs();
        if (frozen) this.mask.outgoingLyrics = null;
        this.mask.draw(this.laid, T, now, t, this.motion, this.hits, t.rainBig * vocalStrength);
        this.spot.update(this.laid, T, dt);
        const aqua = this.aquarium?.step(dt, this.clock.time, this.W / this.H, t, this.aquaBeats()) ?? null;
        if (this.snow) {
            this.snow.step(frozen ? 0 : dt, t, this.mask.sweeps ?? [], this.mask.wet ?? [], this.aquarium ? 0 : t.busSpeed, !this.aquarium);
            this.snow.drawFog(this.mask.ctx, t);
        } else if (this.condensation) this.condensation.touchInk(this.mask.sweeps ?? [], this.mask.wet ?? [], t.dewSize);
        const field = this.condensation ? this.condensation.instances(frozen ? 0 : dt, t.dew, t.dewSize) : this.snow ? this.snow.instances(this.fieldInst) : this.motion.fieldInstances(this.fieldInst, t.busSpeed);
        const u = nebbiaFrameUniforms(t, this.motion.shake(), this.spot, this.W, this.H, this.clock.time, aqua);
        this.gl.render(this.mask.ctx, this.mask.breath.active ? this.mask.breath : null, this.motion.drops, field, u, this.condensation?.changed ?? this.snow?.changed ?? true);
        if (this.snow) this.gl.drawFlakes(...this.snow.flakeInstances(this.mask.ice ?? []), u.glassShift);
        if (this.fireflies) this.gl.drawFireflies(...this.fireflies.step(frozen ? 0 : dt));
        if (!this.firstDrawn) {
            this.firstDrawn = true;
            this.input.onFirstFrame();
        }
        if (!this.paused || this.tfnViewport.moving) this.raf = requestAnimationFrame(this.frame);
    };
}
