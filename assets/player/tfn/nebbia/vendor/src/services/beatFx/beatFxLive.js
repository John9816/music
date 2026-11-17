// TFN supplies realtime spectrum through the renderer input; no fabricated AI stem or beat events.
export const isBeatEffectPlaying = () => false;
export const isBeatFxReady = () => false;
export const getBeatEffectStrength = () => 0;
export const getBeatFxEvents = () => [];
export const getBeatFxHeard = () => ({ key: null, time: null });
