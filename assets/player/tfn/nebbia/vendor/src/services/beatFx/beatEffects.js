// Host contract for optional Folia beat-analysis effects, disabled without their actual analysis data.
export const BEAT_EFFECT_IDS = { nebbiaDrizzleRide: 'nebbiaDrizzleRide', nebbiaAquaBeat: 'nebbiaAquaBeat' };
export const beatEffectPartId = (id, part) => `${id}:${part}`;
