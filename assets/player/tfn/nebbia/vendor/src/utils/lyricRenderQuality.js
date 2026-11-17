// Adapted from Folia 5bdade1102f9b80830eec5f523e87f3e2a13d40d; src/utils/lyricRenderQuality.ts
// Copyright Folia contributors. AGPL-3.0-only. See app/THIRD_PARTY_NOTICES.md.
export const LYRIC_RENDER_QUALITY_STORAGE_KEY = 'lyric_render_quality';
export const LYRIC_RENDER_SCALES = [
    0.5,
    0.75,
    1,
    1.5,
    2
];
export const LYRIC_ANTIALIAS_MODES = [
    'auto',
    'on',
    'off'
];
export const LYRIC_ANTIALIAS_OVERRIDES = [
    'global',
    'on',
    'off'
];
export const DEFAULT_LYRIC_RENDER_QUALITY = {
    scale: 1,
    antialias: 'auto'
};
export const DEFAULT_LYRIC_RENDER_OVERRIDE = {
    scale: 'global',
    antialias: 'global'
};
export const MAX_LYRIC_PIXEL_RATIO = 3;
export const isLyricRenderScale = (value)=>LYRIC_RENDER_SCALES.includes(value);
export const normalizeLyricRenderQuality = (raw)=>{
    const input = raw && typeof raw === 'object' ? raw : {};
    return {
        scale: isLyricRenderScale(input.scale) ? input.scale : DEFAULT_LYRIC_RENDER_QUALITY.scale,
        antialias: LYRIC_ANTIALIAS_MODES.includes(input.antialias) ? input.antialias : DEFAULT_LYRIC_RENDER_QUALITY.antialias
    };
};
export const normalizeLyricRenderOverride = (raw)=>{
    const input = raw && typeof raw === 'object' ? raw : {};
    return {
        scale: isLyricRenderScale(input.scale) ? input.scale : 'global',
        antialias: input.antialias === 'on' || input.antialias === 'off' ? input.antialias : 'global'
    };
};
export const resolveLyricRenderQuality = (global, override)=>({
        scale: override && override.scale !== 'global' ? override.scale : global.scale,
        antialias: override && override.antialias !== 'global' ? override.antialias : global.antialias
    });
export const resolveLyricPixelRatio = (base, scale, max = MAX_LYRIC_PIXEL_RATIO)=>{
    const safeBase = Number.isFinite(base) && base > 0 ? base : 1;
    const ratio = safeBase * scale;
    return scale > 1 ? Math.max(safeBase, Math.min(ratio, max)) : ratio;
};
export const resolveLyricAntialias = (antialias, styleDefault)=>antialias === 'auto' ? styleDefault : antialias === 'on';
export const formatLyricRenderScale = (scale)=>`${scale}×`;
