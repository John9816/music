// Adapted from Folia 5bdade1102f9b80830eec5f523e87f3e2a13d40d; src/utils/fontStacks.ts
// Copyright Folia contributors. AGPL-3.0-only. See app/THIRD_PARTY_NOTICES.md.
export const MIN_FONT_WEIGHT = 100;
export const MAX_FONT_WEIGHT = 900;
export const FONT_WEIGHT_STEP = 10;
export const normalizeFontWeight = (fontWeight)=>{
    if (typeof fontWeight !== 'number' || !Number.isFinite(fontWeight)) return null;
    const clamped = Math.min(MAX_FONT_WEIGHT, Math.max(MIN_FONT_WEIGHT, fontWeight));
    return Math.round(clamped / FONT_WEIGHT_STEP) * FONT_WEIGHT_STEP;
};
export const resolveThemeFontWeight = (theme, fallback)=>normalizeFontWeight(theme?.fontWeight) ?? fallback;
const SUGAR_SERIF_FAMILY = '"獅尾四季春加糖SC"';
export const BUILTIN_FONT_STACKS = {
    sans: '"Inter", "Noto Sans CJK SC", "Noto Sans JP", "Source Han Sans SC", "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", "Helvetica Neue", Arial, sans-serif',
    serif: `${SUGAR_SERIF_FAMILY}, "Iowan Old Style", "Noto Serif CJK SC", "Noto Serif JP", "Source Han Serif SC", "Songti SC", "STSong", "Georgia", serif`,
    mono: '"IBM Plex Mono", "Sarasa Mono SC", "Noto Sans Mono CJK SC", "Noto Sans Mono", "SFMono-Regular", Consolas, monospace'
};
const TRANSLATION_FONT_STACKS = {
    sans: 'system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", "Inter", "Helvetica Neue", Arial, "Noto Sans CJK SC", "Source Han Sans SC", "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", "Noto Sans JP", "Source Han Sans JP", "Hiragino Sans", "Yu Gothic", Meiryo, sans-serif',
    serif: `${SUGAR_SERIF_FAMILY}, "Folia Noto Serif SC", "Iowan Old Style", Georgia, "Times New Roman", "Noto Serif CJK SC", "Source Han Serif SC", "Songti SC", "STSong", "SimSun", "Noto Serif JP", "Source Han Serif JP", "Yu Mincho", "MS PMincho", serif`,
    mono: 'Consolas, "IBM Plex Mono", "SFMono-Regular", Menlo, Monaco, "Sarasa Mono SC", "Noto Sans Mono CJK SC", "SimHei", "DengXian", "Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans Mono CJK JP", "MS Gothic", monospace'
};
const CSS_GENERIC_FONT_FAMILIES = new Set([
    'serif',
    'sans-serif',
    'monospace',
    'cursive',
    'fantasy',
    'system-ui',
    'ui-serif',
    'ui-sans-serif',
    'ui-monospace',
    'ui-rounded',
    'emoji',
    'math',
    'fangsong'
]);
const quoteFontFamily = (fontFamily)=>`"${fontFamily.replace(/["\\]/g, '\\$&')}"`;
const normalizeFontFamilyName = (fontFamily)=>fontFamily.trim().replace(/^['"]|['"]$/g, '').trim();
const formatFontFamily = (fontFamily)=>{
    const normalized = normalizeFontFamilyName(fontFamily);
    if (!normalized) return null;
    return CSS_GENERIC_FONT_FAMILIES.has(normalized.toLowerCase()) ? normalized : quoteFontFamily(normalized);
};
export const normalizeFontFamilyStack = (fontFamilies)=>{
    const seen = new Set();
    const stack = [];
    fontFamilies?.forEach((fontFamily)=>{
        const normalized = normalizeFontFamilyName(fontFamily ?? '');
        if (!normalized) return;
        const key = normalized.toLocaleLowerCase();
        if (seen.has(key)) return;
        seen.add(key);
        stack.push(normalized);
    });
    return stack;
};
const buildCustomFontFamilyStack = (theme)=>{
    const familiesToNormalize = [
        ...theme.fontFamily ? [
            theme.fontFamily
        ] : [],
        ...theme.fontFamilyStack ?? []
    ];
    if (familiesToNormalize.length === 0) {
        return [];
    }
    return normalizeFontFamilyStack(familiesToNormalize).map(formatFontFamily).filter((fontFamily)=>Boolean(fontFamily));
};
export const getBuiltinThemeFontStack = (fontStyle)=>{
    return BUILTIN_FONT_STACKS[fontStyle] ?? BUILTIN_FONT_STACKS.sans;
};
export const resolveThemeFontStack = (theme)=>{
    const fallbackStack = getBuiltinThemeFontStack(theme.fontStyle);
    const customFontStack = buildCustomFontFamilyStack(theme);
    if (customFontStack.length === 0) {
        return fallbackStack;
    }
    return `${customFontStack.join(', ')}, ${fallbackStack}`;
};
export const resolveThemeTranslationFontStack = (theme)=>{
    const fallbackStack = TRANSLATION_FONT_STACKS[theme.fontStyle] ?? TRANSLATION_FONT_STACKS.sans;
    const customFontStack = buildCustomFontFamilyStack(theme);
    if (customFontStack.length === 0) {
        return fallbackStack;
    }
    return `${customFontStack.join(', ')}, ${fallbackStack}`;
};
