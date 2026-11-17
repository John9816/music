// Adapted from Folia 5bdade1102f9b80830eec5f523e87f3e2a13d40d; src/components/visualizer/nebbia/nebbiaDrizzleRide.ts
// Copyright Folia contributors. AGPL-3.0-only. See app/THIRD_PARTY_NOTICES.md.
import { NebbiaDrumBumps } from './nebbiaDrumBumps.js';
import { getDrumHits } from '../../../services/analysis/drumHits.js';
import { getVocalEnvelope } from '../../../services/analysis/vocalEnvelope.js';
import { BEAT_EFFECT_IDS, beatEffectPartId } from '../../../services/beatFx/beatEffects.js';
import { getBeatEffectStrength, getBeatFxHeard, isBeatEffectPlaying } from '../../../services/beatFx/beatFxLive.js';
const DRIZZLE_RIDE = BEAT_EFFECT_IDS.nebbiaDrizzleRide;
const DRIZZLE_RIDE_RAIN = beatEffectPartId(DRIZZLE_RIDE, 'rain');
const DRIZZLE_RIDE_BUMP = beatEffectPartId(DRIZZLE_RIDE, 'bump');
export class NebbiaDrizzleRide {
    drumBumps = new NebbiaDrumBumps();
    env = null;
    rain = 1;
    step(motion, now, T, frozen, bump, bumps = true) {
        const on = isBeatEffectPlaying(DRIZZLE_RIDE);
        const key = on ? getBeatFxHeard().key : null;
        const drums = on && bumps ? getDrumHits(key) : null;
        motion.beginFrame(now, frozen, bumps && !drums);
        if (drums && !frozen) {
            const jolt = this.drumBumps.step(drums, key, T);
            const strength = getBeatEffectStrength(DRIZZLE_RIDE_BUMP);
            if (jolt > 0 && strength > 0 && bump > 0) motion.trigger(now, jolt * strength);
        } else if (!drums) {
            this.drumBumps.reset();
        }
        this.rain = on ? getBeatEffectStrength(DRIZZLE_RIDE_RAIN) : 1;
        this.env = on ? getVocalEnvelope(key) : null;
    }
}
